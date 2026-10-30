import SwiftUI
import UIKit

// MARK: - мои объявления

@MainActor
struct MyView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var meta: Meta
    @StateObject private var feed: FeedModel = {
        let f = FeedModel(path: { _ in "/v1/my/ads" })
        f.paged = false
        return f
    }()
    @State private var path = NavigationPath()
    @State private var sel: Item?
    @State private var promoteFor: Item?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    FeedRows(feed: feed, emptyText: L["no_ads"], extra: status, tap: { sel = $0 })
                }
                .padding(.top, 6)
            }
            .background(Color.page)
            .refreshable { await feed.reload() }
            .navigationTitle(L["my"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { app.tab = 1 } label: { Image(systemName: "plus") }
                }
            }
            .routes()
            .confirmationDialog(sel?.t ?? "", isPresented: Binding(get: { sel != nil }, set: { if !$0 { sel = nil } }),
                                titleVisibility: .visible, presenting: sel) { it in
                Button(L["open"]) { path.append(Route.ad(it.id, it)) }
                if it.s != 2 {
                    Button(L["edit"]) { path.append(Route.edit(it.id)) }
                    Button("🚀 " + L["promote"]) { promoteFor = it }
                    if it.s == 0 { Button(L["hide"]) { setState(it.id, 1) } }
                    else { Button(L["unhide"]) { setState(it.id, 0) } }
                }
                Button(L["delete"], role: .destructive) { delete(it.id) }
            }
            .confirmationDialog(L["promote"], isPresented: Binding(get: { promoteFor != nil }, set: { if !$0 { promoteFor = nil } }),
                                titleVisibility: .visible, presenting: promoteFor) { it in
                ForEach(["bump", "vip7", "vip30"], id: \.self) { s in
                    Button("\(L[s]) — \(money(meta.prices.i64(s)))") { promote(it.id, s) }
                }
            } message: { _ in Text(L["pay_note"]) }
            // обновление при показе, после публикации и после возврата из оплаты
            .task(id: app.myTick) { await feed.reload() }
        }
    }

    private func status(_ it: Item) -> String? {
        var s = L["st\(it.s)"] + " · 👁 \(it.w)"
        if it.x > Int64(Date().timeIntervalSince1970) {
            let f = DateFormatter()
            f.dateFormat = "dd.MM"
            s += " · ⭐ \(L["vip_till"]) " + f.string(from: Date(timeIntervalSince1970: TimeInterval(it.x)))
        }
        return s
    }

    private func setState(_ id: Int64, _ st: Int) {
        Task {
            do { try await Api.call("POST", "/v1/ads/\(id)/state", json: ["st": st]); await feed.reload() }
            catch { Toast.show(errText(error)) }
        }
    }

    private func delete(_ id: Int64) {
        Task {
            do { try await Api.call("DELETE", "/v1/ads/\(id)"); await feed.reload() }
            catch { Toast.show(errText(error)) }
        }
    }
}

// MARK: - профиль

@MainActor
struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var askLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text("👤").font(.system(size: 40))
                        Text("+" + app.me.str("phone")).font(.title3.bold())
                    }
                    .padding(.vertical, 6)
                }
                Section(L["name"]) {
                    TextField(L["name"], text: $name)
                    Button(L["save"]) { Task { await saveName() } }
                }
                Section {
                    NavigationLink(value: Route.fav) { Label(L["fav"], systemImage: "heart") }
                    Picker(selection: Binding(get: { app.tk }, set: { app.setLang($0) })) {
                        Text("Türkmençe").tag(true)
                        Text("Русский").tag(false)
                    } label: { Label(L["lang"], systemImage: "globe") }
                    Button(role: .destructive) { askLogout = true } label: {
                        Label(L["logout"], systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Section {
                    Text("Buşluk 1.0").font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(L["profile"])
            .navigationBarTitleDisplayMode(.inline)
            .routes()
            .confirmationDialog(L["logout_q"], isPresented: $askLogout, titleVisibility: .visible) {
                Button(L["logout"], role: .destructive) { app.logout() }
            }
            .task {
                name = app.me.str("name")
                // имя могло измениться на другом устройстве
                if let u = try? await Api.call("GET", "/v1/me") { store(u); name = u.str("name") }
            }
        }
    }

    private func store(_ u: JSON) {
        if let d = try? JSONSerialization.data(withJSONObject: u) { UserDefaults.standard.set(d, forKey: "me") }
    }

    private func saveName() async {
        do {
            let u = try await Api.call("PUT", "/v1/me", json: ["name": name.trimmingCharacters(in: .whitespaces)])
            store(u)
            Toast.show(L["saved"])
        } catch { Toast.show(errText(error)) }
    }
}

// MARK: - избранное (локально)

@MainActor
struct FavView: View {
    @State private var items: [Item] = []
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    Text(L["fav_empty"]).foregroundColor(.secondary).padding(.top, 40)
                }
                ForEach(items) { it in
                    NavigationLink(value: Route.ad(it.id, it)) { ItemRow(it: it) }.buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .background(Color.page)
        .navigationTitle(L["fav"])
        .onAppear { items = Fav.list().map(Item.init) }
    }
}
