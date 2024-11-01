//
//  SubtitleDataSource.swift
//  KSPlayer-7de52535
//
//  Created by kintan on 2018/8/7.
//
import Foundation

public class EmptySubtitleInfo: SubtitleInfo {
    public var isEnabled: Bool = true
    public let subtitleID: String = ""
    public var delay: TimeInterval = 0
    public let name = NSLocalizedString("no show subtitle", comment: "")
    public func search(for _: TimeInterval, size _: CGSize, isHDR _: Bool) -> [SubtitlePart] {
        []
    }
}

public class URLSubtitleInfo: KSSubtitle, SubtitleInfo {
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled, searchProtocol == nil {
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.parse(url: self.downloadURL, userAgent: self.userAgent)
                }
            }
        }
    }

    public private(set) var downloadURL: URL
    public var delay: TimeInterval = 0
    public private(set) var name: String
    public let subtitleID: String
    public var comment: String?
    public var userInfo: NSMutableDictionary?
    private let userAgent: String?
    public convenience init(url: URL) {
        self.init(subtitleID: url.absoluteString, name: url.lastPathComponent, url: url)
    }

    public init(subtitleID: String, name: String, url: URL, userAgent: String? = nil) {
        self.subtitleID = subtitleID
        self.name = name
        self.userAgent = userAgent
        downloadURL = url
        super.init()
        if !url.isFileURL, name.isEmpty {
            url.download(userAgent: userAgent) { [weak self] filename, tmpUrl in
                guard let self else {
                    return
                }
                self.name = filename
                self.downloadURL = tmpUrl
                var fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                fileURL.appendPathComponent(filename)
                try? FileManager.default.moveItem(at: tmpUrl, to: fileURL)
                self.downloadURL = fileURL
            }
        }
    }
}

public protocol SubtitleDataSource: AnyObject {}

public protocol EmbedSubtitleDataSource: SubtitleDataSource {
    associatedtype Subtitle: SubtitleInfo
    var infos: [Subtitle] { get }
}

public protocol URLSubtitleDataSource: SubtitleDataSource {
    func searchSubtitle(fileURL: URL) async throws -> [URLSubtitleInfo]
}

public protocol SearchSubtitleDataSource: SubtitleDataSource {
    var infos: [URLSubtitleInfo] { get }
    func searchSubtitle(query: String, languages: [String]) async throws -> [URLSubtitleInfo]
}

public protocol CacheSubtitleDataSource: URLSubtitleDataSource {
    func addCache(fileURL: URL, downloadURL: URL)
}

public extension KSOptions {
    @MainActor
    static var subtitleDataSources: [SubtitleDataSource] = [DirectorySubtitleDataSource()]
}

public class PlistCacheSubtitleDataSource: CacheSubtitleDataSource, @unchecked Sendable {
    @MainActor
    public static let singleton = PlistCacheSubtitleDataSource()
    private let srtCacheInfoPath: String
    // 因为plist不能保存URL
    private var srtInfoCaches: [String: [String]]
    private init() {
        let cacheFolder = (NSTemporaryDirectory() as NSString).appendingPathComponent("KSSubtitleCache")
        if !FileManager.default.fileExists(atPath: cacheFolder) {
            try? FileManager.default.createDirectory(atPath: cacheFolder, withIntermediateDirectories: true, attributes: nil)
        }
        srtCacheInfoPath = (cacheFolder as NSString).appendingPathComponent("KSSrtInfo.plist")
        srtInfoCaches = [String: [String]]()
        Task { [weak self] in
            guard let self else {
                return
            }
            srtInfoCaches = (NSMutableDictionary(contentsOfFile: srtCacheInfoPath) as? [String: [String]]) ?? [String: [String]]()
        }
    }

    public func searchSubtitle(fileURL: URL) async throws -> [URLSubtitleInfo] {
        srtInfoCaches[fileURL.absoluteString]?.compactMap { downloadURL -> URLSubtitleInfo? in
            guard let url = URL(string: downloadURL) else {
                return nil
            }
            let info = URLSubtitleInfo(url: url)
            info.comment = "local"
            return info
        } ?? [URLSubtitleInfo]()
    }

    public func addCache(fileURL: URL, downloadURL: URL) {
        let file = fileURL.absoluteString
        let path = downloadURL.absoluteString
        var array = srtInfoCaches[file] ?? [String]()
        if !array.contains(path) {
            array.append(path)
            srtInfoCaches[file] = array
            Task { [weak self] in
                guard let self else {
                    return
                }
                (self.srtInfoCaches as NSDictionary).write(toFile: self.srtCacheInfoPath, atomically: false)
            }
        }
    }
}

public class ConstantURLSubtitleDataSource: URLSubtitleDataSource {
    public let infos: [URLSubtitleInfo]
    public let url: URL
    public init(url: URL, subtitleURLs: [URL]) {
        self.url = url
        infos = subtitleURLs.map { URLSubtitleInfo(url: $0) }
    }

    public func searchSubtitle(fileURL: URL) async throws -> [URLSubtitleInfo] {
        url == fileURL ? infos : []
    }
}

public class DirectorySubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    public func searchSubtitle(fileURL: URL) async throws -> [URLSubtitleInfo] {
        if fileURL.isFileURL {
            let subtitleURLs: [URL] = (try? FileManager.default.contentsOfDirectory(at: fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter(\.isSubtitle)) ?? []
            return subtitleURLs.map { URLSubtitleInfo(url: $0) }.sorted { left, right in
                left.name < right.name
            }
        } else {
            return []
        }
    }
}

public class ShooterSubtitleDataSource: URLSubtitleDataSource {
    public init() {}
    public func searchSubtitle(fileURL: URL) async throws -> [URLSubtitleInfo] {
        guard fileURL.isFileURL, let searchApi = URL(string: "https://www.shooter.cn/api/subapi.php")?
            .add(queryItems: ["format": "json", "pathinfo": fileURL.path, "filehash": fileURL.shooterFilehash])
        else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json.flatMap { sub in
            let filesDic = sub["Files"] as? [[String: String]]
//                let desc = sub["Desc"] as? String ?? ""
            let delay = TimeInterval(sub["Delay"] as? Int ?? 0) / 1000.0
            return filesDic?.compactMap { dic in
                if let string = dic["Link"], let url = URL(string: string) {
                    let info = URLSubtitleInfo(subtitleID: string, name: "", url: url)
                    info.delay = delay
                    return info
                }
                return nil
            } ?? [URLSubtitleInfo]()
        }
    }
}

public class AssrtSubtitleDataSource: SearchSubtitleDataSource {
    private let token: String
    public private(set) var infos = [URLSubtitleInfo]()
    public init(token: String) {
        self.token = token
    }

    public func searchSubtitle(query: String, languages _: [String]) async throws -> [URLSubtitleInfo] {
        guard let searchApi = URL(string: "http://api.assrt.net/v1/sub/search")?.add(queryItems: ["q": query]) else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let status = json["status"] as? Int, status == 0 else {
            return []
        }
        guard let subDict = json["sub"] as? [String: Any], let subArray = subDict["subs"] as? [[String: Any]] else {
            return []
        }
        var result = [URLSubtitleInfo]()
        for sub in subArray {
            if let assrtSubID = sub["id"] as? Int {
                try await result.append(contentsOf: loadDetails(assrtSubID: String(assrtSubID)))
            }
        }
        infos = result
        return result
    }

    func loadDetails(assrtSubID: String) async throws -> [URLSubtitleInfo] {
        var infos = [URLSubtitleInfo]()
        guard let detailApi = URL(string: "http://api.assrt.net/v1/sub/detail")?.add(queryItems: ["id": assrtSubID]) else {
            return infos
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return infos
        }
        guard let status = json["status"] as? Int, status == 0 else {
            return infos
        }
        guard let subDict = json["sub"] as? [String: Any], let subArray = subDict["subs"] as? [[String: Any]], let sub = subArray.first else {
            return infos
        }
        if let fileList = sub["filelist"] as? [[String: String]] {
            for dic in fileList {
                if let urlString = dic["url"], let filename = dic["f"], let url = URL(string: urlString) {
                    let info = URLSubtitleInfo(subtitleID: urlString, name: filename, url: url)
                    infos.append(info)
                }
            }
        } else if let urlString = sub["url"] as? String, let filename = sub["filename"] as? String, let url = URL(string: urlString) {
            let info = URLSubtitleInfo(subtitleID: urlString, name: filename, url: url)
            infos.append(info)
        }
        return infos
    }
}

public class OpenSubtitleDataSource: SearchSubtitleDataSource {
    private var token: String? = nil
    private let username: String?
    private let password: String?
    private let apiKey: String
    public private(set) var infos = [URLSubtitleInfo]()
    public init(apiKey: String, username: String? = nil, password: String? = nil) {
        self.apiKey = apiKey
        self.username = username
        self.password = password
    }

    public func searchSubtitle(query: String, languages: [String]) async throws -> [URLSubtitleInfo] {
        try await searchSubtitle(query: query, imdbID: 0, tmdbID: 0, languages: languages)
    }

    public func searchSubtitle(query: String, imdbID: Int, tmdbID: Int, languages: [String]) async throws -> [URLSubtitleInfo] {
        var queryItems = [String: String]()
        queryItems["query"] = query
        if imdbID != 0 {
            queryItems["imbd_id"] = String(imdbID)
        }
        if tmdbID != 0 {
            queryItems["tmdb_id"] = String(tmdbID)
        }
        queryItems["languages"] = languages.joined(separator: ",")
        return try await searchSubtitle(queryItems: queryItems)
    }

    // https://opensubtitles.stoplight.io/docs/opensubtitles-api/a172317bd5ccc-search-for-subtitles
    public func searchSubtitle(queryItems: [String: String]) async throws -> [URLSubtitleInfo] {
        infos = []
        if queryItems.isEmpty {
            return []
        }
        guard let searchApi = URL(string: "https://api.opensubtitles.com/api/v1/subtitles")?.add(queryItems: queryItems) else {
            return []
        }
        var request = URLRequest(url: searchApi)
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let dataArray = json["data"] as? [[String: Any]] else {
            return []
        }
        var result = [URLSubtitleInfo]()
        for sub in dataArray {
            if let attributes = sub["attributes"] as? [String: Any], let files = attributes["files"] as? [[String: Any]] {
                for file in files {
                    if let fileID = file["file_id"] as? Int, let info = try await loadDetails(fileID: fileID) {
                        result.append(info)
                    }
                }
            }
        }
        infos = result
        return result
    }

    func loadDetails(fileID: Int) async throws -> URLSubtitleInfo? {
        guard let detailApi = URL(string: "https://api.opensubtitles.com/api/v1/download")?.add(queryItems: ["file_id": String(fileID)]) else {
            return nil
        }
        var request = URLRequest(url: detailApi)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "Api-Key")
        if let token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let link = json["link"] as? String, let fileName = json["file_name"] as?
            String, let url = URL(string: link)
        else {
            return nil
        }
        return URLSubtitleInfo(subtitleID: String(fileID), name: fileName, url: url)
    }
}

extension URL {
    public var components: URLComponents? {
        URLComponents(url: self, resolvingAgainstBaseURL: true)
    }

    func add(queryItems: [String: String]) -> URL? {
        guard var urlComponents = components else {
            return nil
        }
        var reserved = CharacterSet.urlQueryAllowed
        reserved.remove(charactersIn: ": #[]@!$&'()*+, ;=")
        urlComponents.percentEncodedQueryItems = queryItems.compactMap { key, value in
            URLQueryItem(name: key.addingPercentEncoding(withAllowedCharacters: reserved) ?? key, value: value.addingPercentEncoding(withAllowedCharacters: reserved))
        }
        return urlComponents.url
    }

    var shooterFilehash: String {
        let file: FileHandle
        do {
            file = try FileHandle(forReadingFrom: self)
        } catch {
            return ""
        }
        defer { file.closeFile() }

        file.seekToEndOfFile()
        let fileSize: UInt64 = file.offsetInFile

        guard fileSize >= 12288 else {
            return ""
        }

        let offsets: [UInt64] = [
            4096,
            fileSize * 2 / 3,
            fileSize / 3,
            fileSize - 8192,
        ]

        let hash = offsets.map { offset -> String in
            file.seek(toFileOffset: offset)
            return file.readData(ofLength: 4096).md5()
        }.joined(separator: ";")
        return hash
    }
}
