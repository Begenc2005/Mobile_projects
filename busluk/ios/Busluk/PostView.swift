import PhotosUI
import SwiftUI
import UIKit

/// Фото в форме: уже на сервере (name) или новое (jpeg ещё не загружен).
struct Slot: Identifiable {
    let id = UUID()
    var name: String?
    var jpeg: Data?
    var preview: UIImage?
}

/// 1280 px по длинной стороне, JPEG 0.75: фото 3–6 МБ превращается в ~200 КБ.
func compress(_ data: Data) -> Slot? {
    guard let img = UIImage(data: data) else { return nil }
    let k = min(1, 1280 / max(img.size.width, img.size.height))
    let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    guard let jpeg = small.jpegData(compressionQuality: 0.75) else { return nil }
    let pk = 200 / max(size.width, size.height)
    let psize = CGSize(width: size.width * pk, height: size.height * pk)
    let prev = UIGraphicsImageRenderer(size: psize, format: fmt).image { _ in small.draw(in: CGRect(origin: .zero, size: psize)) }
    return Slot(name: nil, jpeg: jpeg, preview: prev)
}

@MainActor
struct PostView: View {
    let editId: Int64?
    @EnvironmentObject var meta: Meta
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var g = 0
    @State private var city = UserDefaults.standard.integer(forKey: "last_city")
    @State private var title = ""
    @State private var desc = ""
    @State private var priceText = ""
    @State private var neg = false
    @State private var tel = ""
    @State private var vals: [String: String] = [:]
    @State private var slots: [Slot] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var showCats = false
    @State private var showPlace = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section(L["choose_cat"]) {
                Button { showCats = true } label: {
                    Text(g > 0 ? meta.path(g) : L["choose_cat"]).foregroundColor(g > 0 ? .primary : .brand)
                }
            }
            Section(L["photos"] + " (≤ 8)") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(slots) { s in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let p = s.preview { Image(uiImage: p).resizable().scaledToFill() }
                                    else { RemoteImage(url: s.name.map(Api.thumb)) }
                                }
                                .frame(width: 84, height: 84).clipped().cornerRadius(10)
                                Button { slots.removeAll { $0.id == s.id } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white).shadow(radius: 2).padding(4)
                                }
                            }
                        }
                        if slots.count < 8 {
                            PhotosPicker(selection: $picks, maxSelectionCount: 8 - slots.count, matching: .images) {
                                VStack(spacing: 4) {
                                    Image(systemName: "camera").font(.title2)
                                    Text(L["add_photo"]).font(.caption2).multilineTextAlignment(.center)
                                }
                                .frame(width: 84, height: 84).background(Color.brand.opacity(0.12)).foregroundColor(.brand).cornerRadius(10)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                TextField(L["title"], text: $title)
                TextField(L["desc"], text: $desc, axis: .vertical).lineLimit(4...12)
            }
            let attrs = meta.attrsOf(g)
            if !attrs.isEmpty {
                Section {
                    ForEach(attrs) { a in
                        if a.y == "s" {
                            Picker(a.name, selection: Binding(get: { vals[a.id] ?? "" }, set: { vals[a.id] = $0.isEmpty ? nil : $0 })) {
                                Text("—").tag("")
                                ForEach(a.o, id: \.k) { o in Text(o.name).tag(o.k) }
                            }
                        } else {
                            HStack {
                                Text(a.name).foregroundColor(.secondary)
                                TextField("", text: Binding(get: { vals[a.id] ?? "" },
                                                            set: { vals[a.id] = $0.filter(\.isNumber).isEmpty ? nil : $0.filter(\.isNumber) }))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            Section(L["price"] + ", TMT") {
                TextField("0", text: $priceText).keyboardType(.numberPad)
                Toggle(L["neg"], isOn: $neg)
            }
            Section {
                Button { showPlace = true } label: {
                    HStack {
                        Text(L["city"]).foregroundColor(.primary)
                        Spacer()
                        Text(city > 0 ? meta.city(city) : L["choose_city"]).foregroundColor(city > 0 ? .secondary : .brand)
                    }
                }
                TextField(L["contact_phone"], text: $tel).keyboardType(.phonePad)
            }
            Section {
                MainButton(title: L[editId == nil ? "publish" : "update"], busy: busy) { Task { await submit() } }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L[editId == nil ? "new_ad" : "edit_ad"])
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCats) { CategoryPicker { setCat($0) }.environmentObject(meta) }
        .sheet(isPresented: $showPlace) { PlacePicker(allowAll: false) { _, c in city = c }.environmentObject(meta) }
        .onChange(of: picks) { items in
            guard !items.isEmpty else { return }
            Task {
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let s = compress(d), slots.count < 8 { slots.append(s) }
                }
                picks = []
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if tel.isEmpty, !app.me.str("phone").isEmpty { tel = "+" + app.me.str("phone") }
            if let editId { await load(editId) }
        }
    }

    private func setCat(_ id: Int) {
        if id != g { vals = [:] }
        g = id
    }

    private func load(_ id: Int64) async {
        guard let j = try? await Api.call("GET", "/v1/ads/\(id)") else { return }
        g = j.int("g")
        city = j.int("c")
        title = j.str("t")
        desc = j.str("b")
        priceText = j.i64("p") > 0 ? "\(j.i64("p"))" : ""
        neg = j.bool("n")
        tel = "+" + j.str("tel")
        vals = j.obj("a").mapValues { "\($0)" }
        slots = (j["ph"] as? [String] ?? []).map { Slot(name: $0) }
    }

    private func reset() {
        g = 0; title = ""; desc = ""; priceText = ""; neg = false; vals = [:]; slots = []
    }

    private func submit() async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if g == 0 { return Toast.show(L["e_cat"]) }
        if city == 0 { return Toast.show(L["e_city"]) }
        if t.count < 3 { return Toast.show(L["e_title"]) }
        UserDefaults.standard.set(city, forKey: "last_city")
        busy = true
        defer { busy = false }
        do {
            // новые фото — по одному; загруженные раньше повторно не отправляются
            for i in slots.indices where slots[i].name == nil {
                if let jpeg = slots[i].jpeg {
                    slots[i].name = try await Api.call("POST", "/v1/photo", raw: jpeg).str("f")
                }
            }
            var a: JSON = [:]
            for attr in meta.attrsOf(g) {
                guard let v = vals[attr.id] else { continue }
                a[attr.id] = attr.y == "n" ? (Int64(v) ?? 0) as Any : v as Any
            }
            let body: JSON = [
                "g": g, "c": city, "t": t, "b": desc.trimmingCharacters(in: .whitespacesAndNewlines),
                "p": Int64(priceText.filter(\.isNumber)) ?? 0, "n": neg, "a": a,
                "ph": slots.compactMap(\.name), "tel": tel,
            ]
            if let editId {
                try await Api.call("PUT", "/v1/ads/\(editId)", json: body)
                Toast.show(L["saved"])
                dismiss()
            } else {
                try await Api.call("POST", "/v1/ads", json: body)
                Toast.show(L["published"])
                reset()
                app.myTick += 1
                app.tab = 2
            }
        } catch {
            Toast.show(errText(error))
        }
    }
}

/// Выбор категории: раздел -> подраздел.
@MainActor
struct CategoryPicker: View {
    let done: (Int) -> Void
    @EnvironmentObject var meta: Meta
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(meta.tops) { t in
                if meta.children(t.id).isEmpty {
                    Button { done(t.id); dismiss() } label: { row(t) }
                } else {
                    NavigationLink {
                        List(meta.children(t.id)) { c in
                            Button { done(c.id); dismiss() } label: { row(c) }
                        }
                        .navigationTitle(t.name)
                    } label: { row(t) }
                }
            }
            .navigationTitle(L["choose_cat"])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L["cancel"]) { dismiss() } } }
        }
    }

    private func row(_ c: Cat) -> some View {
        HStack { Text(c.e).font(.title3); Text(c.name).foregroundColor(.primary) }
    }
}
