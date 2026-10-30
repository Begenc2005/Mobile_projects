import SwiftUI
import UIKit

typealias JSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { self[k] as? String ?? "" }
    func int(_ k: String) -> Int { (self[k] as? NSNumber)?.intValue ?? 0 }
    func i64(_ k: String) -> Int64 { (self[k] as? NSNumber)?.int64Value ?? 0 }
    func bool(_ k: String) -> Bool { (self[k] as? NSNumber)?.boolValue ?? false }
    func arr(_ k: String) -> [JSON] { self[k] as? [JSON] ?? [] }
    func obj(_ k: String) -> JSON { self[k] as? JSON ?? [:] }
}

struct ApiError: Error { let code: String; let http: Int }

func errText(_ e: Error) -> String {
    let code = (e as? ApiError)?.code ?? "net"
    let t = L["e_" + code]
    return t.hasPrefix("e_") ? L["net"] : t
}

/// Сеть: URLSession + JSONSerialization, без библиотек. gzip URLSession распаковывает сам.
enum Api {
    static let base = "https://busluk.tm"   // адрес сервера (только HTTPS)

    static var token: String? {
        get { UserDefaults.standard.string(forKey: "tok") }
        set { UserDefaults.standard.set(newValue, forKey: "tok") }
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    static var onUnauthorized: (() -> Void)?

    @discardableResult
    static func call(_ method: String, _ path: String, json: JSON? = nil, raw: Data? = nil,
                     etag: String? = nil) async throws -> JSON {
        guard let url = URL(string: base + path) else { throw ApiError(code: "net", http: 0) }
        var r = URLRequest(url: url)
        r.httpMethod = method
        if let t = token { r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        if let e = etag { r.setValue(e, forHTTPHeaderField: "If-None-Match") }
        if let raw {
            r.httpBody = raw
            r.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        } else if let json {
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let pair: (Data, URLResponse)
        do { pair = try await session.data(for: r) } catch { throw ApiError(code: "net", http: 0) }
        let (data, resp) = pair
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 304 { return ["_304": true] }
        var j = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        if code >= 400 {
            if code == 401 { await MainActor.run { onUnauthorized?() } }
            throw ApiError(code: j.str("e").isEmpty ? "net" : j.str("e"), http: code)
        }
        if let et = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") { j["_etag"] = et }
        return j
    }

    static func thumb(_ f: String) -> String { "\(base)/i/\(f)_t.jpg" }
    static func full(_ f: String) -> String { "\(base)/i/\(f).jpg" }
}

// MARK: - модели

struct Item: Identifiable, Hashable {
    let id: Int64
    let t: String
    let p: Int64
    let n: Bool
    let c: Int
    let g: Int
    let f: String
    let d: Int64
    let v: Bool
    let s: Int
    let x: Int64
    let w: Int

    init(_ j: JSON) {
        id = j.i64("i"); t = j.str("t"); p = j.i64("p"); n = j.bool("n"); c = j.int("c"); g = j.int("g")
        f = j.str("f"); d = j.i64("d"); v = j.bool("v"); s = j.int("s"); x = j.i64("x"); w = j.int("w")
    }

    var json: JSON { ["i": id, "t": t, "p": p, "n": n, "c": c, "g": g, "f": f, "d": d] }
}

struct Cat: Identifiable { let id: Int; let p: Int; let r: String; let t: String; let e: String; let a: [String]
    var name: String { L.pick(r, t) } }
struct Opt: Hashable { let k: String; let r: String; let t: String; var name: String { L.pick(r, t) } }
struct Attr: Identifiable { let id: String; let r: String; let t: String; let y: String; let u: String; let o: [Opt]
    var name: String { L.pick(r, t) + (u.isEmpty ? "" : ", \(u)") }
    func optName(_ k: String) -> String { o.first { $0.k == k }?.name ?? k } }
struct Place: Identifiable { let id: Int; let g: Int; let r: String; let t: String; var name: String { L.pick(r, t) } }

/// Справочники: один запрос, кэш на диске, повторно — только если изменились (ETag).
@MainActor final class Meta: ObservableObject {
    static let shared = Meta()
    @Published var cats: [Cat] = []
    var attrs: [String: Attr] = [:]
    var cities: [Place] = []
    var regions: [Place] = []
    var prices: JSON = [:]
    var ready: Bool { !cats.isEmpty }

    private var file: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("meta.json") }

    init() {
        if let d = try? Data(contentsOf: file), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON { parse(j) }
    }

    func refresh() async {
        let et = ready ? UserDefaults.standard.string(forKey: "meta_etag") : nil
        guard var j = try? await Api.call("GET", "/v1/meta", etag: et), j["_304"] == nil else { return }
        let tag = j.str("_etag")
        j["_etag"] = nil
        if let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: file) }
        UserDefaults.standard.set(tag, forKey: "meta_etag")
        parse(j)
    }

    private func parse(_ j: JSON) {
        cats = j.arr("cats").map { Cat(id: $0.int("i"), p: $0.int("p"), r: $0.str("r"), t: $0.str("t"), e: $0.str("e"), a: $0["a"] as? [String] ?? []) }
        var m: [String: Attr] = [:]
        for a in j.arr("attrs") {
            let o = a.arr("o").map { Opt(k: $0.str("k"), r: $0.str("r"), t: $0.str("t")) }
            m[a.str("k")] = Attr(id: a.str("k"), r: a.str("r"), t: a.str("t"), y: a.str("y"), u: a.str("u"), o: o)
        }
        attrs = m
        let pl = { (a: [JSON]) in a.map { Place(id: $0.int("i"), g: $0.int("g"), r: $0.str("r"), t: $0.str("t")) } }
        cities = pl(j.arr("cities"))
        regions = pl(j.arr("regions"))
        prices = j.obj("prices")
    }

    func cat(_ id: Int) -> Cat? { cats.first { $0.id == id } }
    func children(_ id: Int) -> [Cat] { cats.filter { $0.p == id } }
    var tops: [Cat] { cats.filter { $0.p == 0 } }
    func city(_ id: Int) -> String { cities.first { $0.id == id }?.name ?? "" }
    func attrsOf(_ id: Int) -> [Attr] {
        guard let c = cat(id) else { return [] }
        let keys = c.a.isEmpty && c.p != 0 ? (cat(c.p)?.a ?? []) : c.a
        return keys.compactMap { attrs[$0] }
    }
    func path(_ id: Int) -> String {
        guard let c = cat(id) else { return "" }
        if let p = cat(c.p) { return "\(p.name) › \(c.name)" }
        return c.name
    }
}

// MARK: - параметры поиска

struct Query: Hashable {
    var q = ""
    var g = 0
    var c = 0
    var r = 0
    var pmin = ""
    var pmax = ""
    var s = ""
    var ph = false
    var f: [String: String] = [:]

    var filterCount: Int { [pmin, pmax].filter { !$0.isEmpty }.count + (ph ? 1 : 0) + f.count }

    func path(_ off: Int) -> String {
        var p: [(String, String)] = [("o", "\(off)")]
        if !q.isEmpty { p.append(("q", q)) }
        if g > 0 { p.append(("g", "\(g)")) }
        if c > 0 { p.append(("c", "\(c)")) } else if r > 0 { p.append(("r", "\(r)")) }
        if !pmin.isEmpty { p.append(("pmin", pmin)) }
        if !pmax.isEmpty { p.append(("pmax", pmax)) }
        if !s.isEmpty { p.append(("s", s)) }
        if ph { p.append(("ph", "1")) }
        if !f.isEmpty { p.append(("f", f.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        return "/v1/ads?" + p.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }
}

// MARK: - лента с подгрузкой страниц

@MainActor final class FeedModel: ObservableObject {
    enum State: Equatable { case idle, loading, empty, error(String) }
    @Published var items: [Item] = []
    @Published var vip: [Item] = []
    @Published var cats: [Int] = []
    @Published var state: State = .idle
    var path: (Int) -> String
    var paged = true
    private var hasMore = true
    private var busy = false
    private var gen = 0

    init(path: @escaping (Int) -> String = { "/v1/ads?o=\($0)" }) { self.path = path }

    func reload() async {
        gen += 1
        hasMore = true
        busy = false
        items = []
        vip = []
        cats = []
        await next()
    }

    func next() async {
        guard hasMore, !busy else { return }
        busy = true
        let my = gen
        state = .loading
        do {
            let j = try await Api.call("GET", path(items.count))
            guard my == gen else { return }
            if items.isEmpty {
                vip = j.arr("vip").map(Item.init)
                cats = j["cats"] as? [Int] ?? []
            }
            let seen = Set(items.map(\.id))
            items += j.arr("items").map(Item.init).filter { !seen.contains($0.id) }
            hasMore = paged && j.bool("more")
            state = items.isEmpty && !hasMore ? .empty : .idle
        } catch {
            guard my == gen else { return }
            state = .error(errText(error))
            hasMore = false
        }
        busy = false
    }

    func retry() async { hasMore = true; await next() }

    /// вызывается при появлении карточки: за 4 до конца — следующая страница
    func appeared(_ it: Item) {
        guard let i = items.firstIndex(of: it), i >= items.count - 4 else { return }
        Task { await next() }
    }
}

// MARK: - картинки: память + дисковый URLCache (сервер отдаёт фото как immutable)

enum ImageCache {
    static let mem: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.totalCostLimit = 40 << 20; return c }()
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 80 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    static func load(_ s: String) async -> UIImage? {
        if let m = mem.object(forKey: s as NSString) { return m }
        guard let u = URL(string: s), let res = try? await session.data(from: u), let img = UIImage(data: res.0) else { return nil }
        let d = res.0
        mem.setObject(img, forKey: s as NSString, cost: d.count * 4)
        return img
    }
}

@MainActor
struct RemoteImage: View {
    let url: String?
    var fit = false
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGray5)
            if let img {
                if fit { Image(uiImage: img).resizable().scaledToFit() }
                else { Image(uiImage: img).resizable().scaledToFill() }
            }
        }
        .clipped()
        .task(id: url) {
            img = nil
            if let url { img = await ImageCache.load(url) }
        }
    }
}

// MARK: - избранное (только на телефоне)

enum Fav {
    static func list() -> [JSON] {
        guard let d = UserDefaults.standard.data(forKey: "fav"),
              let a = (try? JSONSerialization.jsonObject(with: d)) as? [JSON] else { return [] }
        return a
    }
    static func has(_ id: Int64) -> Bool { list().contains { $0.i64("i") == id } }
    @discardableResult static func toggle(_ it: JSON) -> Bool {
        let id = it.i64("i")
        var l = list().filter { $0.i64("i") != id }
        let added = l.count == list().count
        if added { l.insert(it, at: 0) }
        if let d = try? JSONSerialization.data(withJSONObject: Array(l.prefix(300))) { UserDefaults.standard.set(d, forKey: "fav") }
        return added
    }
}

// MARK: - форматирование

func money(_ p: Int64) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{00A0}"
    return (f.string(from: NSNumber(value: p)) ?? "\(p)") + "\u{00A0}TMT"
}

func price(_ p: Int64, _ neg: Bool) -> String {
    if p > 0 && neg { return money(p) + " · " + L["neg"] }
    if p > 0 { return money(p) }
    return neg ? L["neg"] : L["no_price"]
}

func ago(_ unix: Int64) -> String {
    let d = Date(timeIntervalSince1970: TimeInterval(unix))
    let cal = Calendar.current
    let hm = DateFormatter()
    hm.dateFormat = "HH:mm"
    if cal.isDateInToday(d) { return L["today"] + " " + hm.string(from: d) }
    if cal.isDateInYesterday(d) { return L["yesterday"] + " " + hm.string(from: d) }
    hm.dateFormat = "dd.MM.yyyy"
    return hm.string(from: d)
}

/// Продвижение: создаёт платёж и открывает страницу банка в Safari.
func promote(_ ad: Int64, _ svc: String) {
    Task {
        do {
            let j = try await Api.call("POST", "/v1/pay", json: ["ad": ad, "svc": svc])
            if let u = URL(string: j.str("url")) { await UIApplication.shared.open(u) }
        } catch {
            await MainActor.run { Toast.show(errText(error)) }
        }
    }
}
