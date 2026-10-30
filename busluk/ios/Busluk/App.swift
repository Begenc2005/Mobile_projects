import SwiftUI

extension Color {
    static let brand = Color(red: 0.04, green: 0.49, blue: 0.31)     // #0A7D4F
    static let gold = Color(red: 0.95, green: 0.72, blue: 0.02)      // #F2B705
    static let card = Color(.secondarySystemGroupedBackground)
    static let page = Color(.systemGroupedBackground)
}

@MainActor final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var tk = UserDefaults.standard.string(forKey: "lang") != "ru"
    @Published var langChosen = UserDefaults.standard.string(forKey: "lang") != nil
    @Published var loggedIn = Api.token != nil
    @Published var tab = 0
    @Published var toast: String?
    @Published var myTick = 0            // обновить «Мои» (после оплаты / публикации)

    init() {
        L.tk = tk
        Api.onUnauthorized = { [weak self] in
            Api.token = nil
            self?.loggedIn = false
        }
    }

    func setLang(_ tk: Bool) {
        UserDefaults.standard.set(tk ? "tk" : "ru", forKey: "lang")
        L.tk = tk
        self.tk = tk
        langChosen = true
    }

    func login(token: String, user: JSON) {
        Api.token = token
        if let d = try? JSONSerialization.data(withJSONObject: user) { UserDefaults.standard.set(d, forKey: "me") }
        tab = 0
        loggedIn = true
    }

    func logout() {
        Task {
            _ = try? await Api.call("POST", "/v1/auth/logout")
            Api.token = nil
        }
        UserDefaults.standard.removeObject(forKey: "me")
        loggedIn = false
    }

    var me: JSON {
        guard let d = UserDefaults.standard.data(forKey: "me"), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else { return [:] }
        return j
    }
}

@MainActor enum Toast {
    static func show(_ s: String) {
        AppState.shared.toast = s
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if AppState.shared.toast == s { AppState.shared.toast = nil }
        }
    }
}

@main
@MainActor
struct BuslukApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var meta = Meta.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(meta)
                .tint(.brand)
                // возврат из Safari после оплаты (busluk://paid) или просто в приложение
                .onOpenURL { _ in app.myTick += 1 }
                .onChange(of: phase) { p in if p == .active { app.myTick += 1 } }
        }
    }
}

@MainActor
struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if !app.langChosen { LangView() }
            else if !app.loggedIn { LoginView() }
            else { MainTabs() }
        }
        .id(app.tk)   // смена языка — пересобрать интерфейс
        .overlay(alignment: .bottom) {
            if let t = app.toast {
                Text(t).font(.subheadline).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.8)).cornerRadius(20)
                    .padding(.bottom, 90).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
    }
}

@MainActor
struct MainTabs: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView(selection: $app.tab) {
            HomeView().tabItem { Label(L["home"], systemImage: "house") }.tag(0)
            NavigationStack { PostView(editId: nil) }.tabItem { Label(L["post"], systemImage: "plus.circle") }.tag(1)
            MyView().tabItem { Label(L["my"], systemImage: "list.bullet.rectangle") }.tag(2)
            ProfileView().tabItem { Label(L["profile"], systemImage: "person") }.tag(3)
        }
    }
}

// MARK: - навигация

enum Route: Hashable {
    case cat(Int)
    case results(Query)
    case ad(Int64, Item?)
    case edit(Int64)
    case fav
}

@MainActor
struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .cat(let id): CatView(id: id)
        case .results(let q): ResultsView(initial: q)
        case .ad(let id, let it): AdView(id: id, preview: it)
        case .edit(let id): PostView(editId: id)
        case .fav: FavView()
        }
    }
}

extension View {
    func routes() -> some View { navigationDestination(for: Route.self) { RouteView(route: $0) } }
}

// MARK: - язык

@MainActor
struct LangView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("📣").font(.system(size: 64))
            Text("Buşluk").font(.system(size: 38, weight: .bold)).foregroundColor(.white)
            Text("Türkmenistanyň bildirişleri\nОбъявления Туркменистана").multilineTextAlignment(.center).foregroundColor(.white.opacity(0.9))
            Spacer()
            langButton("Türkmençe") { app.setLang(true) }
            langButton("Русский") { app.setLang(false) }
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brand.ignoresSafeArea())
    }

    func langButton(_ t: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(t).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.white).foregroundColor(.brand).cornerRadius(12)
        }
    }
}

// MARK: - вход

@MainActor
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var phone = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @FocusState private var codeFocus: Bool

    private var full: String { "993" + String(phone.filter(\.isNumber).suffix(8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("📣 Buşluk").font(.system(size: 30, weight: .bold)).foregroundColor(.brand).padding(.top, 30)
                Text(L["welcome"]).foregroundColor(.secondary)
                if !sent {
                    Text(L["phone"]).font(.subheadline).foregroundColor(.secondary).padding(.top, 24)
                    HStack {
                        Text("+993").font(.title3.bold())
                        TextField("65 123456", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .font(.title3).padding(12).background(Color.card).cornerRadius(10)
                    }
                    MainButton(title: L["get_code"], busy: busy) { Task { await send() } }
                } else {
                    Text("\(L["code_sent"]) +\(full)").foregroundColor(.secondary).padding(.top, 24)
                    TextField("••••••", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)   // iOS сам подставит код из SMS
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(12).background(Color.card).cornerRadius(10)
                        .focused($codeFocus)
                        .onChange(of: code) { c in if c.count == 6 && !busy { Task { await verify() } } }
                    MainButton(title: L["login"], busy: busy) { Task { await verify() } }
                    Button(L["resend"]) { Task { await send() } }.padding(.top, 6)
                    Button(L["change_phone"]) { sent = false; code = "" }
                }
            }
            .padding(24)
        }
        .background(Color.page.ignoresSafeArea())
    }

    func send() async {
        busy = true
        defer { busy = false }
        do {
            try await Api.call("POST", "/v1/auth/send", json: ["phone": full])
            sent = true
            code = ""
            codeFocus = true
        } catch { Toast.show(errText(error)) }
    }

    func verify() async {
        busy = true
        defer { busy = false }
        do {
            let j = try await Api.call("POST", "/v1/auth/verify", json: ["phone": full, "code": code])
            app.login(token: j.str("token"), user: j.obj("user"))
        } catch { Toast.show(errText(error)) }
    }
}

@MainActor
struct MainButton: View {
    let title: String
    var busy = false
    var secondary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(secondary ? .brand : .white) }
                else { Text(title).font(.headline) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(secondary ? Color.brand.opacity(0.12) : Color.brand)
            .foregroundColor(secondary ? .brand : .white)
            .cornerRadius(12)
        }
        .disabled(busy)
    }
}
