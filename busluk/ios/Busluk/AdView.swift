import SwiftUI
import UIKit

@MainActor
struct AdView: View {
    let id: Int64
    let preview: Item?
    @EnvironmentObject var meta: Meta
    @State private var ad: JSON?
    @State private var error: String?
    @State private var fav = false
    @State private var page = 0
    @State private var viewer = false
    @State private var promoteAsk = false

    private var photos: [String] {
        if let ad { return ad["ph"] as? [String] ?? [] }
        if let f = preview?.f, !f.isEmpty { return [f] }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !photos.isEmpty {
                    // полное фото грузится только здесь; в ленте — миниатюры
                    TabView(selection: $page) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, f in
                            RemoteImage(url: ad == nil ? Api.thumb(f) : Api.full(f)).tag(i)
                                .onTapGesture { if ad != nil { viewer = true } }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                    .frame(height: 290)
                }
                info.padding(16)
            }
        }
        .background(Color.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { toggleFav() } label: { Image(systemName: fav ? "heart.fill" : "heart") }
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                Menu {
                    ForEach(["r_fraud", "r_spam", "r_sold", "r_cat"], id: \.self) { r in
                        Button(L[r]) { report(r) }
                    }
                } label: { Image(systemName: "exclamationmark.bubble") }
            }
        }
        .safeAreaInset(edge: .bottom) { if let ad { bottomBar(ad) } }
        .fullScreenCover(isPresented: $viewer) { PhotoViewer(photos: photos, index: page) }
        .confirmationDialog(L["promote"], isPresented: $promoteAsk, titleVisibility: .visible) {
            ForEach(["bump", "vip7", "vip30"], id: \.self) { s in
                Button("\(L[s]) — \(money(meta.prices.i64(s)))") { promote(id, s) }
            }
        } message: { Text(L["pay_note"]) }
        .task {
            fav = Fav.has(id)
            do { ad = try await Api.call("GET", "/v1/ads/\(id)") } catch { self.error = errText(error) }
        }
    }

    @ViewBuilder private var info: some View {
        let j: JSON = ad ?? preview?.json ?? [:]
        if j.isEmpty, let error {
            Text(error).foregroundColor(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
        } else if j.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if j.bool("v") || preview?.v == true {
                    Text("⭐ VIP").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.gold).cornerRadius(8)
                }
                Text(price(j.i64("p"), j.bool("n"))).font(.title2.bold())
                Text(j.str("t")).font(.title3)
                Text("📍 \(meta.city(j.int("c"))) · \(ago(j.i64("d")))" + (ad != nil ? " · 👁 \(j.int("seen"))" : ""))
                    .font(.footnote).foregroundColor(.secondary)
                Text(meta.path(j.int("g"))).font(.footnote).foregroundColor(.brand)

                let attrs = j.obj("a")
                let shown = meta.attrsOf(j.int("g")).filter { attrs[$0.id] != nil }
                if !shown.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(shown) { a in
                            let raw = "\(attrs[a.id]!)"
                            HStack {
                                Text(a.name).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                Text(a.y == "s" ? a.optName(raw) : raw).bold().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(12).background(Color.card).cornerRadius(12).padding(.top, 10)
                }
                if !j.str("b").isEmpty {
                    Text(L["desc"]).font(.headline).padding(.top, 14)
                    Text(j.str("b")).textSelection(.enabled)
                }
                if !j.str("u").isEmpty {
                    Text("👤 \(L["seller"]): \(j.str("u"))").font(.subheadline).foregroundColor(.secondary).padding(.top, 14)
                }
                Text("№ \(id)").font(.caption).foregroundColor(.secondary).padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func bottomBar(_ j: JSON) -> some View {
        HStack(spacing: 8) {
            if j.bool("own") {
                NavigationLink(value: Route.edit(id)) {
                    Text(L["edit"]).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.brand.opacity(0.12)).foregroundColor(.brand).cornerRadius(12)
                }
                MainButton(title: L["promote"]) { promoteAsk = true }
            } else if j.str("tel").isEmpty {
                Text(L["login_to_see"]).foregroundColor(.secondary).frame(maxWidth: .infinity)
            } else {
                let tel = j.str("tel")
                MainButton(title: "📞 " + L["call"]) { open("tel:+\(tel)") }.layoutPriority(1)
                MainButton(title: L["sms"], secondary: true) { open("sms:+\(tel)") }.frame(width: 110)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var shareText: String {
        let j: JSON = ad ?? preview?.json ?? [:]
        var s = j.str("t") + "\n" + price(j.i64("p"), j.bool("n"))
        if !j.str("tel").isEmpty { s += "\n☎ +" + j.str("tel") }
        return s + "\n— Buşluk"
    }

    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }

    private func toggleFav() {
        let j: JSON = ad ?? preview?.json ?? [:]
        var short: JSON = [:]
        for k in ["i", "t", "p", "n", "c", "g", "d"] { short[k] = j[k] }
        short["i"] = id
        short["f"] = photos.first ?? ""
        fav = Fav.toggle(short)
    }

    private func report(_ r: String) {
        Task {
            do { try await Api.call("POST", "/v1/ads/\(id)/report", json: ["reason": r]); Toast.show(L["report_ok"]) }
            catch { Toast.show(errText(error)) }
        }
    }
}

@MainActor
struct PhotoViewer: View {
    let photos: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, f in
                    RemoteImage(url: Api.full(f), fit: true).background(Color.black).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title2).foregroundColor(.white).padding(18)
            }
        }
    }
}
