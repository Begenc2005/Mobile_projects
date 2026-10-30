import SwiftUI

// MARK: - карточка в ленте

@MainActor
struct ItemRow: View {
    let it: Item
    var extra: String? = nil
    @EnvironmentObject var meta: Meta

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: it.f.isEmpty ? nil : Api.thumb(it.f))
                .frame(width: 96, height: 96).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text((it.v ? "⭐ " : "") + it.t).font(.subheadline).lineLimit(2).foregroundColor(.primary)
                Text(price(it.p, it.n)).font(.headline).foregroundColor(.primary).lineLimit(1)
                Text(extra ?? "\(meta.city(it.c)) · \(ago(it.d))").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(it.v ? Color.gold.opacity(0.16) : Color.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(it.v ? Color.gold : .clear, lineWidth: 1))
        .cornerRadius(14)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}

@MainActor
struct VipStrip: View {
    let items: [Item]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⭐ " + L["vip"]).font(.headline).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { it in
                        NavigationLink(value: Route.ad(it.id, it)) {
                            VStack(alignment: .leading, spacing: 4) {
                                RemoteImage(url: it.f.isEmpty ? nil : Api.thumb(it.f)).frame(width: 140, height: 100).cornerRadius(10)
                                Text(it.t).font(.footnote).lineLimit(2).foregroundColor(.primary).frame(width: 140, alignment: .leading)
                                Text(price(it.p, it.n)).font(.subheadline.bold()).foregroundColor(.primary).lineLimit(1).frame(width: 140, alignment: .leading)
                            }
                            .padding(8).background(Color.gold.opacity(0.16))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gold, lineWidth: 1)).cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Список объявлений модели + подвал (загрузка / пусто / ошибка).
@MainActor
struct FeedRows: View {
    @ObservedObject var feed: FeedModel
    var emptyText = L["empty"]
    var extra: ((Item) -> String?)? = nil
    var tap: ((Item) -> Void)? = nil

    var body: some View {
        ForEach(feed.items) { it in
            Group {
                if let tap {
                    Button { tap(it) } label: { ItemRow(it: it, extra: extra?(it)) }
                } else {
                    NavigationLink(value: Route.ad(it.id, it)) { ItemRow(it: it, extra: extra?(it)) }
                }
            }
            .buttonStyle(.plain)
            .onAppear { feed.appeared(it) }
        }
        Group {
            switch feed.state {
            case .loading: ProgressView().padding(24)
            case .empty: Text(emptyText).foregroundColor(.secondary).padding(30)
            case .error(let e):
                Button { Task { await feed.retry() } } label: {
                    Text(e + "\n↻ " + L["retry"]).multilineTextAlignment(.center)
                }.padding(24)
            case .idle: Color.clear.frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
struct Chip: View {
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Color.brand : Color.card)
                .foregroundColor(on ? .white : .primary)
                .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - поиск с подсказками

@MainActor
struct SearchBar: View {
    @Binding var text: String
    let onSubmit: (String) -> Void
    let onCat: (Int) -> Void
    @EnvironmentObject var meta: Meta
    @FocusState private var focused: Bool
    @State private var sCats: [Int] = []
    @State private var sTitles: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(L["search_hint"], text: $text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { submit() }
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color(.systemBackground)).cornerRadius(22)

            if focused && !(sCats.isEmpty && sTitles.isEmpty) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sCats, id: \.self) { id in
                        line("\(meta.cat(id)?.e ?? "")  \(meta.path(id))") { focused = false; onCat(id) }
                    }
                    ForEach(sTitles, id: \.self) { t in
                        line("🔍  " + t) { text = t; submit() }
                    }
                }
                .background(Color(.systemBackground)).cornerRadius(12)
            }
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
        .background(Color.brand)
        // пауза в наборе 0.4 с — только тогда запрос (меньше трафика)
        .task(id: text) {
            let q = text.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { sCats = []; sTitles = []; return }
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            let enc = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            guard let j = try? await Api.call("GET", "/v1/suggest?q=" + enc) else { return }
            sCats = j["cats"] as? [Int] ?? []
            sTitles = j["t"] as? [String] ?? []
        }
    }

    private func submit() {
        focused = false
        sCats = []
        sTitles = []
        onSubmit(text.trimmingCharacters(in: .whitespaces))
    }

    private func line(_ s: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(s).lineLimit(1).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
}

// MARK: - главная

@MainActor
struct HomeView: View {
    @EnvironmentObject var meta: Meta
    @StateObject private var feed = FeedModel()
    @State private var path = NavigationPath()
    @State private var text = ""

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SearchBar(text: $text, onSubmit: { q in
                        if !q.isEmpty { path.append(Route.results(Query(q: q))) }
                    }, onCat: { id in path.append(Route.results(Query(g: id))) })

                    Text(L["cats"]).font(.headline).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(meta.tops) { c in
                            NavigationLink(value: meta.children(c.id).isEmpty ? Route.results(Query(g: c.id)) : Route.cat(c.id)) {
                                VStack(spacing: 4) {
                                    Text(c.e).font(.system(size: 26)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(Color.card).cornerRadius(16)
                                    Text(c.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)

                    if !feed.vip.isEmpty { VipStrip(items: feed.vip).padding(.top, 8) }
                    Text(L["fresh"]).font(.headline).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                    FeedRows(feed: feed)
                }
            }
            .background(Color.page)
            .refreshable { await feed.reload() }
            .navigationTitle("Buşluk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brand, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .routes()
            .task {
                if feed.items.isEmpty {
                    if !meta.ready { await meta.refresh() } else { Task { await meta.refresh() } }
                    await feed.reload()
                }
            }
        }
    }
}

// MARK: - подкатегории

@MainActor
struct CatView: View {
    let id: Int
    @EnvironmentObject var meta: Meta

    var body: some View {
        List {
            NavigationLink(value: Route.results(Query(g: id))) { Label(L["all_in"], systemImage: "square.grid.2x2").font(.headline) }
            ForEach(meta.children(id)) { c in
                NavigationLink(value: meta.children(c.id).isEmpty ? Route.results(Query(g: c.id)) : Route.cat(c.id)) {
                    HStack { Text(c.e).font(.title3); Text(c.name) }
                }
            }
        }
        .navigationTitle(meta.cat(id)?.name ?? "")
    }
}

// MARK: - результаты

@MainActor
struct ResultsView: View {
    @State var query: Query
    @State private var text: String
    @StateObject private var feed = FeedModel()
    @State private var showFilters = false
    @State private var showPlace = false
    @EnvironmentObject var meta: Meta

    init(initial: Query) {
        _query = State(initialValue: initial)
        _text = State(initialValue: initial.q)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SearchBar(text: $text, onSubmit: { q in query.q = q }, onCat: { id in query.g = id; query.f = [:] })
                chips
                if !feed.cats.isEmpty && query.g == 0 { found }
                if !feed.vip.isEmpty { VipStrip(items: feed.vip) }
                FeedRows(feed: feed)
            }
        }
        .background(Color.page)
        .refreshable { await feed.reload() }
        .navigationTitle(query.g > 0 ? (meta.cat(query.g)?.name ?? "") : L["search_hint"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFilters = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showFilters) { FilterView(query: $query).environmentObject(meta) }
        .sheet(isPresented: $showPlace) {
            PlacePicker(allowAll: true) { r, c in query.r = r; query.c = c }.environmentObject(meta)
        }
        .task(id: query) {
            let q = query
            feed.path = { q.path($0) }
            await feed.reload()
        }
    }

    private var placeName: String {
        if query.c > 0 { return meta.city(query.c) }
        if query.r > 0 { return meta.regions.first { $0.id == query.r }?.name ?? "" }
        return L["all_tm"]
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "📍 " + placeName, on: query.c > 0 || query.r > 0) { showPlace = true }
                Menu {
                    Button(L["s_new"]) { query.s = "" }
                    Button(L["s_cheap"]) { query.s = "cheap" }
                    Button(L["s_dear"]) { query.s = "dear" }
                } label: {
                    Chip(title: "↕ " + L[query.s == "cheap" ? "s_cheap" : query.s == "dear" ? "s_dear" : "s_new"], on: !query.s.isEmpty) {}
                        .allowsHitTesting(false)
                }
                let n = query.filterCount
                Chip(title: "⚙ " + L["filters"] + (n > 0 ? " · \(n)" : ""), on: n > 0) { showFilters = true }
                if query.g > 0 {
                    let parent = meta.cat(query.g)?.p ?? 0
                    let subs = meta.children(query.g).isEmpty ? meta.children(parent) : meta.children(query.g)
                    ForEach(subs) { s in
                        Chip(title: s.name, on: s.id == query.g) {
                            query.g = (s.id == query.g && parent > 0) ? parent : s.id
                            query.f = [:]
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var found: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L["found"]).font(.caption).foregroundColor(.secondary).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(feed.cats, id: \.self) { id in
                        if let c = meta.cat(id) { Chip(title: "\(c.e) \(c.name)") { query.g = id } }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - выбор места

@MainActor
struct PlacePicker: View {
    let allowAll: Bool
    let done: (Int, Int) -> Void
    @EnvironmentObject var meta: Meta
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if allowAll {
                    Button(L["all_tm"]) { done(0, 0); dismiss() }
                }
                ForEach(meta.regions) { r in
                    let cs = meta.cities.filter { $0.g == r.id }
                    Section(r.name) {
                        if allowAll && cs.count > 1 {
                            Button(L["any"] + " — " + r.name) { done(r.id, 0); dismiss() }
                        }
                        ForEach(cs) { c in
                            Button(c.name) { done(r.id, c.id); dismiss() }.foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(L["city"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L["cancel"]) { dismiss() } } }
        }
    }
}

// MARK: - фильтры

@MainActor
struct FilterView: View {
    @Binding var query: Query
    @State private var draft = Query()
    @EnvironmentObject var meta: Meta
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L["price"] + ", TMT") {
                    HStack {
                        TextField(L["from"], text: $draft.pmin).keyboardType(.numberPad)
                        Divider()
                        TextField(L["to"], text: $draft.pmax).keyboardType(.numberPad)
                    }
                    Toggle(L["with_photo"], isOn: $draft.ph)
                }
                let attrs = meta.attrsOf(draft.g)
                if !attrs.isEmpty {
                    Section {
                        ForEach(attrs) { a in
                            if a.y == "s" {
                                Picker(a.name, selection: Binding(get: { draft.f[a.id] ?? "" },
                                                                  set: { draft.f[a.id] = $0.isEmpty ? nil : $0 })) {
                                    Text(L["any"]).tag("")
                                    ForEach(a.o, id: \.k) { o in Text(o.name).tag(o.k) }
                                }
                            } else {
                                HStack {
                                    Text(a.name).foregroundColor(.secondary)
                                    TextField(L["from"], text: range(a.id, 0)).keyboardType(.numberPad)
                                    TextField(L["to"], text: range(a.id, 1)).keyboardType(.numberPad)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L["filters"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L["reset"]) {
                        var q = Query(); q.q = query.q; q.g = query.g
                        query = q
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L["apply"]) { query = draft; dismiss() }.bold()
                }
            }
            .onAppear { draft = query }
        }
    }

    /// числовой диапазон хранится как "от-до" (например year: "2010-2018")
    private func range(_ k: String, _ i: Int) -> Binding<String> {
        Binding(get: {
            let p = (draft.f[k] ?? "-").components(separatedBy: "-")
            return i < p.count ? p[i] : ""
        }, set: { v in
            var p = (draft.f[k] ?? "-").components(separatedBy: "-")
            while p.count < 2 { p.append("") }
            p[i] = v.filter(\.isNumber)
            draft.f[k] = p.joined().isEmpty ? nil : p[0] + "-" + p[1]
        })
    }
}
