import Combine
import SwiftUI
import UIKit
import AVFoundation
import AVKit
import WebKit
import UniformTypeIdentifiers

private func makeYouTubeSearchURL(_ query: String) -> URL? {
    guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        return nil
    }

    return URL(string: "https://www.youtube.com/results?search_query=\(encodedQuery)")
}

private func makeBillboardYearEndURL() -> URL? {
    URL(string: "https://ca.billboard.com/charts/year-end/top-artists")
}

private func makeBillboardWeeklyURL(_ date: String) -> URL? {
    URL(string: "https://ca.billboard.com/charts/billboard-200/\(date)")
}

// ── MARK: Colour Palette ──────────────────────────────────────────
extension Color {
    static let nomoBG      = Color(hex: "#0A0A0F")
    static let nomoPurple  = Color(hex: "#7C3AED")
    static let nomoViolet  = Color(hex: "#A855F7")
    static let nomoGlow    = Color(hex: "#C084FC")
    static let nomoPink    = Color(hex: "#EC4899")
    static let nomoCard    = Color(hex: "#16161F")
    static let nomoGray    = Color(hex: "#9CA3AF")
    static let nomoMidGray = Color(hex: "#374151")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// ── MARK: Models ──────────────────────────────────────────────

struct Clip: Identifiable {
    let id = UUID()
    let songTitle: String
    let duration: String
    let source: ClipSource
    let videoURL: URL?
}

enum ClipSource: String {
    case user      = "person.fill"
    case youtube   = "play.rectangle.fill"
    case instagram = "camera.fill"

    var label: String {
        switch self {
        case .user:      return "Fan Upload"
        case .youtube:   return "YouTube"
        case .instagram: return "Instagram"
        }
    }
}

struct Concert: Identifiable {
    let id = UUID()
    let tourName: String
    let year: Int
    let venue: String
    let city: String
    let date: String
    let clipCount: Int
    let rating: Double
    let genres: [String]
    let clips: [Clip]
}

struct Artist: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let emoji: String
    let totalConcerts: Int
    let yearRange: String
    let concerts: [Concert]
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.id == rhs.id }

    var isChartSample: Bool {
        concerts.count == 1 && concerts.first?.isChartRecord == true
    }

    var archiveSummary: String {
        isChartSample ? "1 chart record archived" : "\(totalConcerts) concerts archived"
    }

    var discoverySummary: String {
        isChartSample ? yearRange : "\(totalConcerts) concerts"
    }

    var resultSummary: String {
        isChartSample ? yearRange : "\(yearRange) • \(totalConcerts) concerts"
    }

    var assetName: String {
        let specialCases: [String: String] = [
            "Ty Dolla $ign": "artist-ty-dolla-sign"
        ]

        if let specialCase = specialCases[name] {
            return specialCase
        }

        let normalized = name
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "$", with: " sign ")
            .lowercased()

        let parts = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return "artist-\(parts.joined(separator: "-"))"
    }

    var remoteImageLookupName: String {
        let searchOverrides: [String: String] = [
            "Kanye West": "Ye",
            "J. Cole": "J Cole",
            "The Kid LAROI": "Kid Laroi",
            "Guns N' Roses": "Guns N Roses",
            "Wham!": "Wham",
            "Tiesto": "Tiësto",
            "Michael Buble": "Michael Bublé",
            "Bob Marley and the Wailers": "Bob Marley",
            "Creedence Clearwater Revival": "CCR",
            "ABBA": "Abba"
        ]

        return searchOverrides[name] ?? name
    }

    var remoteImageOverrideURL: URL? {
        let imageOverrides: [String: URL?] = [
            "Snaughty": URL(string: "https://i.iheart.com/v3/catalog/artist/40365905?ops=fit(480,480),run(\"circle\")"),
            "SSJMEECH": URL(string: "https://i.iheart.com/v3/catalog/artist/40845149?ops=fit(480,480),run(\"circle\")")
        ]

        return imageOverrides[name] ?? nil
    }
}

struct ForYouRecommendation: Identifiable {
    let id = UUID()
    let artist: Artist
    let concert: Concert
    let clip: Clip
    let reason: String
    let accent: Color
}

struct HomeFeedSnapshot {
    let featuredArtist: Artist
    let featuredConcert: Concert
    let forYouPicks: [ForYouRecommendation]
    let trendingArtists: [Artist]
    let refreshedAt: Date
}

struct ArtistPlaybackRoute: Identifiable {
    let id = UUID()
    let artist: Artist
    let concert: Concert
    let clip: Clip
}

struct PlayerTrack: Identifiable, Hashable {
    let id = UUID()
    let artist: Artist
    let concert: Concert
    let clip: Clip

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PlayerTrack, rhs: PlayerTrack) -> Bool { lhs.id == rhs.id }
}

struct UploadedVideo: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let artistName: String
    let tourName: String
    let fileName: String
    let importedAt: Date

    var fileURL: URL {
        VideoUploadStore.uploadsDirectory.appendingPathComponent(fileName)
    }

    var displaySubtitle: String {
        "\(artistName) • \(tourName)"
    }
}

enum VideoUploadStore {
    static var uploadsDirectory: URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return baseURL.appendingPathComponent("UploadedVideos", isDirectory: true)
    }

    private static var metadataURL: URL {
        uploadsDirectory.appendingPathComponent("uploads.json")
    }

    static func loadUploads() -> [UploadedVideo] {
        ensureDirectoryExists()

        guard
            let data = try? Data(contentsOf: metadataURL),
            let uploads = try? JSONDecoder().decode([UploadedVideo].self, from: data)
        else {
            return []
        }

        return uploads.sorted { $0.importedAt > $1.importedAt }
    }

    static func importVideo(from sourceURL: URL, title: String, artistName: String, tourName: String) throws -> UploadedVideo {
        ensureDirectoryExists()

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let safeTitle = sanitizedFileStem(from: title)
        let destinationFileName = "\(UUID().uuidString)-\(safeTitle).\(fileExtension)"
        let destinationURL = uploadsDirectory.appendingPathComponent(destinationFileName)

        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let upload = UploadedVideo(
            id: UUID(),
            title: title,
            artistName: artistName,
            tourName: tourName,
            fileName: destinationFileName,
            importedAt: Date()
        )

        var uploads = loadUploads()
        uploads.insert(upload, at: 0)
        try saveUploads(uploads)
        return upload
    }

    static func delete(_ upload: UploadedVideo) throws {
        var uploads = loadUploads()
        uploads.removeAll { $0.id == upload.id }
        try saveUploads(uploads)

        if FileManager.default.fileExists(atPath: upload.fileURL.path) {
            try FileManager.default.removeItem(at: upload.fileURL)
        }
    }

    private static func saveUploads(_ uploads: [UploadedVideo]) throws {
        ensureDirectoryExists()
        let data = try JSONEncoder().encode(uploads)
        try data.write(to: metadataURL, options: [.atomic])
    }

    private static func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: uploadsDirectory.path) {
            try? FileManager.default.createDirectory(at: uploadsDirectory, withIntermediateDirectories: true)
        }
    }

    private static func sanitizedFileStem(from title: String) -> String {
        let pieces = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return pieces.isEmpty ? "clip" : pieces.joined(separator: "-")
    }
}

actor ArtistImageService {
    static let shared = ArtistImageService()

    private var cache: [String: URL?] = [:]

    func imageURL(for artistName: String) async -> URL? {
        if let cached = cache[artistName] {
            return cached
        }

        guard
            let encodedName = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://api.deezer.com/search/artist?q=\(encodedName)")
        else {
            cache[artistName] = nil
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let artists = jsonObject?["data"] as? [[String: Any]]
            let imageURLString = artists?.first?["picture_xl"] as? String
            let imageURL = imageURLString.flatMap(URL.init(string:))
            cache[artistName] = imageURL
            return imageURL
        } catch {
            cache[artistName] = nil
            return nil
        }
    }
}

actor AudioPreviewService {
    static let shared = AudioPreviewService()

    struct TrackLookup {
        let previewURL: URL?
        let fullTrackURL: URL?
    }

    private var cache: [String: TrackLookup?] = [:]

    func lookup(for track: PlayerTrack) async -> TrackLookup? {
        let exactKey = "\(track.artist.name)|\(track.clip.songTitle)"
        if let cached = cache[exactKey] {
            return cached
        }

        if let exactMatch = await searchPreview(term: "\(track.artist.name) \(track.clip.songTitle)") {
            cache[exactKey] = exactMatch
            return exactMatch
        }

        let artistKey = "\(track.artist.name)|artist-fallback"
        if let cachedArtistMatch = cache[artistKey] {
            cache[exactKey] = cachedArtistMatch
            return cachedArtistMatch
        }

        let artistMatch = await searchPreview(term: track.artist.name)
        cache[artistKey] = artistMatch
        cache[exactKey] = artistMatch
        return artistMatch
    }

    private func searchPreview(term: String) async -> TrackLookup? {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "https://itunes.apple.com/search?term=\(encodedTerm)&media=music&entity=song&limit=1"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = jsonObject?["results"] as? [[String: Any]]
            let previewURLString = results?.first?["previewUrl"] as? String
            let fullTrackURLString = (results?.first?["trackViewUrl"] as? String) ?? (results?.first?["collectionViewUrl"] as? String)
            return TrackLookup(
                previewURL: previewURLString.flatMap(URL.init(string:)),
                fullTrackURL: fullTrackURLString.flatMap(URL.init(string:))
            )
        } catch {
            return nil
        }
    }
}

actor CatalogTrackInfoService {
    static let shared = CatalogTrackInfoService()

    struct TrackInfo {
        let title: String?
        let album: String?
        let year: String?
    }

    private var cache: [String: TrackInfo?] = [:]

    func trackInfo(for artistName: String) async -> TrackInfo? {
        if let cached = cache[artistName] {
            return cached
        }

        guard let encodedTerm = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            cache[artistName] = nil
            return nil
        }

        let urlString = "https://itunes.apple.com/search?term=\(encodedTerm)&media=music&entity=song&limit=1"
        guard let url = URL(string: urlString) else {
            cache[artistName] = nil
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = jsonObject?["results"] as? [[String: Any]]
            let title = results?.first?["trackName"] as? String
            let album = results?.first?["collectionName"] as? String
            let releaseDate = results?.first?["releaseDate"] as? String
            let year = releaseDate.flatMap { String($0.prefix(4)) }
            let info = TrackInfo(title: title, album: album, year: year)
            cache[artistName] = info
            return info
        } catch {
            cache[artistName] = nil
            return nil
        }
    }
}

extension Concert: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Concert, rhs: Concert) -> Bool { lhs.id == rhs.id }

    var isChartRecord: Bool {
        genres.contains("Chart")
    }

    var rowSummary: String {
        isChartRecord ? date : "\(year) • \(clipCount) clips"
    }

    var detailHeadline: String {
        isChartRecord ? "Chart Record" : "Concert Video"
    }

    var detailSubheadline: String {
        isChartRecord ? "\(venue) • \(date)" : "\(venue) • \(date)"
    }
}

// ── MARK: Sample Data ─────────────────────────────────────────

extension Artist {
    static let ssjmeechSpotlight = Artist(
        name: "SSJMEECH",
        emoji: "🎤",
        totalConcerts: 1,
        yearRange: "iHeart • 2024–2026",
        concerts: [
            Concert(
                tourName: "xannybar",
                year: 2026,
                venue: "iHeart",
                city: "Streaming Spotlight",
                date: "January 2026 • 2 songs",
                clipCount: 5,
                rating: 4.3,
                genres: ["Hip-Hop/Rap", "Streaming"],
                clips: [
                    Clip(
                        songTitle: "newswag",
                        duration: "Search",
                        source: .youtube,
                        videoURL: makeYouTubeSearchURL("SSJMEECH newswag")
                    ),
                    Clip(
                        songTitle: "sometimes i feel sad then i pop x",
                        duration: "1:00",
                        source: .youtube,
                        videoURL: makeYouTubeSearchURL("SSJMEECH sometimes i feel sad then i pop x")
                    )
                ]
            )
        ]
    )

    static let snaughtySpotlight = Artist(
        name: "Snaughty",
        emoji: "🎤",
        totalConcerts: 1,
        yearRange: "Apple Music • 2023–2026",
        concerts: [
            Concert(
                tourName: "Until I Rott - EP",
                year: 2025,
                venue: "Apple Music",
                city: "Streaming Spotlight",
                date: "May 28, 2025 • 4919503 Records DK",
                clipCount: 5,
                rating: 4.4,
                genres: ["Hip-Hop/Rap", "Streaming"],
                clips: [
                    Clip(
                        songTitle: "Area 29 (feat. Camye)",
                        duration: "2:57",
                        source: .youtube,
                        videoURL: makeYouTubeSearchURL("Snaughty Area 29 feat Camye")
                    ),
                    Clip(
                        songTitle: "Hedi Slimane Boot",
                        duration: "Search",
                        source: .youtube,
                        videoURL: makeYouTubeSearchURL("Snaughty Hedi Slimane Boot")
                    )
                ]
            )
        ]
    )

    static let editorialPicks: [Artist] = [
        Artist(name: "Beyoncé", emoji: "👑", totalConcerts: 847, yearRange: "1992 – 2023", concerts: [
            Concert(tourName: "Renaissance World Tour", year: 2023, venue: "SoFi Stadium", city: "Los Angeles, CA", date: "Sep 4, 2023", clipCount: 56, rating: 4.9, genres: ["Pop", "R&B", "HD"], clips: [
                Clip(songTitle: "Opening / CUFF IT", duration: "0:52", source: .user, videoURL: makeYouTubeSearchURL("Beyonce CUFF IT live")),
                Clip(songTitle: "ALIEN SUPERSTAR", duration: "4:12", source: .youtube, videoURL: makeYouTubeSearchURL("Beyonce ALIEN SUPERSTAR live"))
            ])
        ]),
        Artist(name: "Michael Jackson", emoji: "🌕", totalConcerts: 612, yearRange: "1984 – 2009", concerts: [
            Concert(tourName: "Bad World Tour", year: 1987, venue: "Wembley Stadium", city: "London, UK", date: "Jul 15, 1988", clipCount: 142, rating: 5.0, genres: ["Pop"], clips: [
                Clip(songTitle: "Thriller", duration: "6:57", source: .youtube, videoURL: URL(string: "https://www.youtube.com/watch?v=sOnqjkJTMaA")),
                Clip(songTitle: "Billie Jean", duration: "4:54", source: .instagram, videoURL: makeYouTubeSearchURL("Michael Jackson Billie Jean live"))
            ])
        ]),
        Artist(name: "Nirvana", emoji: "🎤", totalConcerts: 389, yearRange: "1987 – 1994", concerts: [
            Concert(tourName: "In Utero Tour", year: 1993, venue: "Seattle Center Coliseum", city: "Seattle, WA", date: "Jan 7, 1994", clipCount: 37, rating: 4.8, genres: ["Rock", "Grunge"], clips: [
                Clip(songTitle: "Heart-Shaped Box", duration: "4:41", source: .youtube, videoURL: makeYouTubeSearchURL("Nirvana Heart-Shaped Box official video"))
            ])
        ]),
        Artist(name: "Prince", emoji: "🎸", totalConcerts: 1024, yearRange: "1979 – 2016", concerts: [
            Concert(tourName: "Purple Rain Tour", year: 1984, venue: "First Avenue", city: "Minneapolis, MN", date: "Aug 3, 1984", clipCount: 52, rating: 5.0, genres: ["Rock", "Funk"], clips: [
                Clip(songTitle: "Purple Rain", duration: "8:41", source: .youtube, videoURL: makeYouTubeSearchURL("Prince Purple Rain official video"))
            ])
        ]),
        Artist(name: "Radiohead", emoji: "🌀", totalConcerts: 247, yearRange: "1991 – 2018", concerts: [
            Concert(tourName: "OK Computer Tour", year: 1997, venue: "Glastonbury Festival", city: "Somerset, UK", date: "Jun 28, 1997", clipCount: 29, rating: 5.0, genres: ["Alt", "Rock"], clips: [
                Clip(songTitle: "Paranoid Android", duration: "6:23", source: .youtube, videoURL: makeYouTubeSearchURL("Radiohead Paranoid Android official video"))
            ])
        ])
    ]

    static let billboardSampleArtists: [Artist] = [
        (name: "Taylor Swift", source: "Billboard Canada Top Artists 2024 #1", year: 2024),
        (name: "Morgan Wallen", source: "Billboard Canada Top Artists 2024 #2", year: 2024),
        (name: "Zach Bryan", source: "Billboard Canada Top Artists 2024 #3", year: 2024),
        (name: "Drake", source: "Billboard Canada Top Artists 2024 #4", year: 2024),
        (name: "Noah Kahan", source: "Billboard Canada Top Artists 2024 #5", year: 2024),
        (name: "Sabrina Carpenter", source: "Billboard Canada Top Artists 2024 #6", year: 2024),
        (name: "Luke Combs", source: "Billboard Canada Top Artists 2024 #7", year: 2024),
        (name: "Post Malone", source: "Billboard Canada Top Artists 2024 #8", year: 2024),
        (name: "Eminem", source: "Billboard Canada Top Artists 2024 #9", year: 2024),
        (name: "Billie Eilish", source: "Billboard Canada Top Artists 2024 #10", year: 2024),
        (name: "Benson Boone", source: "Billboard Canada Top Artists 2024 #11", year: 2024),
        (name: "Olivia Rodrigo", source: "Billboard Canada Top Artists 2024 #12", year: 2024),
        (name: "Travis Scott", source: "Billboard Canada Top Artists 2024 #13", year: 2024),
        (name: "Tate McRae", source: "Billboard Canada Top Artists 2024 #14", year: 2024),
        (name: "The Weeknd", source: "Billboard Canada Top Artists 2024 #15", year: 2024),
        (name: "Teddy Swims", source: "Billboard Canada Top Artists 2024 #16", year: 2024),
        (name: "Kendrick Lamar", source: "Billboard Canada Top Artists 2024 #17", year: 2024),
        (name: "Shaboozey", source: "Billboard Canada Top Artists 2024 #18", year: 2024),
        (name: "Hozier", source: "Billboard Canada Top Artists 2024 #19", year: 2024),
        (name: "Chappell Roan", source: "Billboard Canada Top Artists 2024 #20", year: 2024),
        (name: "Ariana Grande", source: "Billboard Canada Top Artists 2024 #21", year: 2024),
        (name: "SZA", source: "Billboard Canada Top Artists 2024 #22", year: 2024),
        (name: "Dua Lipa", source: "Billboard Canada Top Artists 2024 #23", year: 2024),
        (name: "Metro Boomin", source: "Billboard Canada Top Artists 2024 #24", year: 2024),
        (name: "Chris Stapleton", source: "Billboard Canada Top Artists 2024 #25", year: 2024),
        (name: "Kanye West", source: "Billboard Canada Top Artists 2024 #26", year: 2024),
        (name: "21 Savage", source: "Billboard Canada Top Artists 2024 #27", year: 2024),
        (name: "Elton John", source: "Billboard Canada Top Artists 2024 #28", year: 2024),
        (name: "Doja Cat", source: "Billboard Canada Top Artists 2024 #30", year: 2024),
        (name: "Frank Ocean", source: "Billboard Canada Top Artists 2024 #31", year: 2024),
        (name: "Future", source: "Billboard Canada Top Artists 2024 #32", year: 2024),
        (name: "Miley Cyrus", source: "Billboard Canada Top Artists 2024 #33", year: 2024),
        (name: "Creedence Clearwater Revival", source: "Billboard Canada Top Artists 2024 #34", year: 2024),
        (name: "Dasha", source: "Billboard Canada Top Artists 2024 #35", year: 2024),
        (name: "Bailey Zimmerman", source: "Billboard Canada Top Artists 2024 #36", year: 2024),
        (name: "Charli XCX", source: "Billboard Canada Top Artists 2024 #37", year: 2024),
        (name: "Ed Sheeran", source: "Billboard Canada Top Artists 2024 #38", year: 2024),
        (name: "Fleetwood Mac", source: "Billboard Canada Top Artists 2024 #39", year: 2024),
        (name: "Nicki Minaj", source: "Billboard Canada Top Artists 2024 #40", year: 2024),
        (name: "Pitbull", source: "Billboard Canada Top Artists 2024 #41", year: 2024),
        (name: "Jack Harlow", source: "Billboard Canada Top Artists 2024 #42", year: 2024),
        (name: "Queen", source: "Billboard Canada Top Artists 2024 #43", year: 2024),
        (name: "Gunna", source: "Billboard Canada Top Artists 2024 #44", year: 2024),
        (name: "Tommy Richman", source: "Billboard Canada Top Artists 2024 #45", year: 2024),
        (name: "Michael Buble", source: "Billboard Canada Top Artists 2024 #46", year: 2024),
        (name: "ABBA", source: "Billboard Canada Top Artists 2024 #47", year: 2024),
        (name: "Ty Dolla $ign", source: "Billboard Canada Top Artists 2024 #48", year: 2024),
        (name: "Jelly Roll", source: "Billboard Canada Top Artists 2024 #49", year: 2024),
        (name: "Les Cowboys Fringants", source: "Billboard Canada Top Artists 2024 #50", year: 2024),
        (name: "Lana Del Rey", source: "Billboard Canada Top Artists 2024 #51", year: 2024),
        (name: "Linkin Park", source: "Billboard Canada Top Artists 2024 #52", year: 2024),
        (name: "Gracie Abrams", source: "Billboard Canada Top Artists 2024 #53", year: 2024),
        (name: "Nickelback", source: "Billboard Canada Top Artists 2024 #54", year: 2024),
        (name: "Katy Perry", source: "Billboard Canada Top Artists 2024 #55", year: 2024),
        (name: "The Kid LAROI", source: "Billboard Canada Top Artists 2024 #56", year: 2024),
        (name: "Lady Gaga", source: "Billboard Canada Top Artists 2024 #57", year: 2024),
        (name: "Tyla", source: "Billboard Canada Top Artists 2024 #58", year: 2024),
        (name: "Charlotte Cardin", source: "Billboard Canada Top Artists 2024 #59", year: 2024),
        (name: "Thomas Rhett", source: "Billboard Canada Top Artists 2024 #60", year: 2024),
        (name: "J. Cole", source: "Billboard Canada Top Artists 2024 #61", year: 2024),
        (name: "Mariah Carey", source: "Billboard Canada Top Artists 2024 #62", year: 2024),
        (name: "Don Toliver", source: "Billboard Canada Top Artists 2024 #63", year: 2024),
        (name: "The Beatles", source: "Billboard Canada Top Artists 2024 #64", year: 2024),
        (name: "Bob Marley and the Wailers", source: "Billboard Canada Top Artists 2024 #65", year: 2024),
        (name: "Djo", source: "Billboard Canada Top Artists 2024 #66", year: 2024),
        (name: "Eagles", source: "Billboard Canada Top Artists 2024 #67", year: 2024),
        (name: "Lewis Capaldi", source: "Billboard Canada Top Artists 2024 #68", year: 2024),
        (name: "Jung Kook", source: "Billboard Canada Top Artists 2024 #69", year: 2024),
        (name: "Myles Smith", source: "Billboard Canada Top Artists 2024 #70", year: 2024),
        (name: "Arctic Monkeys", source: "Billboard Canada Top Artists 2024 #71", year: 2024),
        (name: "Guns N' Roses", source: "Billboard Canada Top Artists 2024 #72", year: 2024),
        (name: "Yeat", source: "Billboard Canada Top Artists 2024 #73", year: 2024),
        (name: "Harry Styles", source: "Billboard Canada Top Artists 2024 #74", year: 2024),
        (name: "Kacey Musgraves", source: "Billboard Canada Top Artists 2024 #75", year: 2024),
        (name: "The Tragically Hip", source: "Billboard Canada Top Artists 2024 #76", year: 2024),
        (name: "Michael Marcagi", source: "Billboard Canada Top Artists 2024 #77", year: 2024),
        (name: "Journey", source: "Billboard Canada Top Artists 2024 #78", year: 2024),
        (name: "Mitski", source: "Billboard Canada Top Artists 2024 #79", year: 2024),
        (name: "Paul Russell", source: "Billboard Canada Top Artists 2024 #80", year: 2024),
        (name: "Artemas", source: "Billboard Canada Top Artists 2024 #81", year: 2024),
        (name: "Brenda Lee", source: "Billboard Canada Top Artists 2024 #82", year: 2024),
        (name: "50 Cent", source: "Billboard Canada Top Artists 2024 #83", year: 2024),
        (name: "Lil Tecca", source: "Billboard Canada Top Artists 2024 #84", year: 2024),
        (name: "OneRepublic", source: "Billboard Canada Top Artists 2024 #85", year: 2024),
        (name: "Wham!", source: "Billboard Canada Top Artists 2024 #86", year: 2024),
        (name: "Nate Smith", source: "Billboard Canada Top Artists 2024 #87", year: 2024),
        (name: "Bad Bunny", source: "Billboard Canada Top Artists 2024 #88", year: 2024),
        (name: "Kane Brown", source: "Billboard Canada Top Artists 2024 #89", year: 2024),
        (name: "Andy Williams", source: "Billboard Canada Top Artists 2024 #90", year: 2024),
        (name: "Playboi Carti", source: "Billboard Canada Top Artists 2024 #91", year: 2024),
        (name: "Tiesto", source: "Billboard Canada Top Artists 2024 #92", year: 2024),
        (name: "Maroon 5", source: "Billboard Canada Top Artists 2024 #93", year: 2024),
        (name: "Bon Jovi", source: "Billboard Canada Top Artists 2024 #94", year: 2024),
        (name: "Nat King Cole", source: "Billboard Canada Top Artists 2024 #95", year: 2024),
        (name: "Foo Fighters", source: "Billboard Canada Top Artists 2024 #96", year: 2024),
        (name: "Bryson Tiller", source: "Billboard Canada Top Artists 2024 #97", year: 2024),
        (name: "Bing Crosby", source: "Billboard Canada Top Artists 2024 #98", year: 2024),
        (name: "Marshmello", source: "Billboard Canada Top Artists 2024 #99", year: 2024),
        (name: "Kelly Clarkson", source: "Billboard Canada Top Artists 2024 #100", year: 2024),
        (name: "Olivia Dean", source: "Billboard 200 week of January 31, 2026", year: 2026)
    ].enumerated().map { index, entry in
        makeBillboardSampleArtist(name: entry.name, source: entry.source, year: entry.year, index: index)
    }

    static let all: [Artist] = editorialPicks + [snaughtySpotlight, ssjmeechSpotlight] + billboardSampleArtists

    static let libraryTracks: [PlayerTrack] = all.flatMap { artist in
        artist.concerts.flatMap { concert in
            concert.clips.map { clip in
                PlayerTrack(artist: artist, concert: concert, clip: clip)
            }
        }
    }

    static let forYouPicks: [ForYouRecommendation] = [
        ForYouRecommendation(
            artist: snaughtySpotlight,
            concert: snaughtySpotlight.concerts[0],
            clip: snaughtySpotlight.concerts[0].clips[0],
            reason: "Underground rap discovery",
            accent: .nomoPink
        ),
        ForYouRecommendation(
            artist: editorialPicks[1],
            concert: editorialPicks[1].concerts[0],
            clip: editorialPicks[1].concerts[0].clips[0],
            reason: "Iconic live performance",
            accent: .nomoViolet
        ),
        ForYouRecommendation(
            artist: editorialPicks[2],
            concert: editorialPicks[2].concerts[0],
            clip: editorialPicks[2].concerts[0].clips[0],
            reason: "Raw 90s alternative energy",
            accent: .nomoGlow
        ),
        ForYouRecommendation(
            artist: editorialPicks[3],
            concert: editorialPicks[3].concerts[0],
            clip: editorialPicks[3].concerts[0].clips[0],
            reason: "Legendary guitar moment",
            accent: .nomoPurple
        ),
        ForYouRecommendation(
            artist: editorialPicks[4],
            concert: editorialPicks[4].concerts[0],
            clip: editorialPicks[4].concerts[0].clips[0],
            reason: "Essential alt-rock archive",
            accent: .nomoPink
        )
    ]

    static let homeFeedRefreshInterval: TimeInterval = 45

    private static let homeFeedReasons = [
        "Underground rap discovery",
        "Iconic live performance",
        "Raw 90s alternative energy",
        "Legendary guitar moment",
        "Essential alt-rock archive",
        "Festival set worth revisiting",
        "Chart-dominating catalog run",
        "Late-night headphone replay",
        "Archive clip fans keep sharing",
        "Fresh catalog rabbit hole"
    ]

    private static let homeFeedAccents: [Color] = [
        .nomoPink,
        .nomoViolet,
        .nomoGlow,
        .nomoPurple
    ]

    private static var featuredCandidates: [Artist] {
        [snaughtySpotlight, ssjmeechSpotlight] + editorialPicks + Array(billboardSampleArtists.prefix(16))
    }

    private static var refreshableForYouPool: [ForYouRecommendation] {
        let pool = featuredCandidates.filter { !$0.concerts.isEmpty && !($0.concerts.first?.clips.isEmpty ?? true) }

        return pool.enumerated().map { index, artist in
            let concert = artist.concerts[0]
            let clip = concert.clips[0]
            return ForYouRecommendation(
                artist: artist,
                concert: concert,
                clip: clip,
                reason: homeFeedReasons[index % homeFeedReasons.count],
                accent: homeFeedAccents[index % homeFeedAccents.count]
            )
        }
    }

    static func homeFeed(at date: Date = .now) -> HomeFeedSnapshot {
        let artists = featuredCandidates.filter { !$0.concerts.isEmpty }
        let refreshIndex = max(Int(date.timeIntervalSince1970 / homeFeedRefreshInterval), 0)
        let featuredArtist = rotated(artists, by: refreshIndex).first ?? artists[0]
        let featuredConcert = featuredArtist.concerts[0]
        let refreshedForYou = Array(rotated(refreshableForYouPool, by: refreshIndex * 2).prefix(5))
        let trendingArtists = Array(rotated(all, by: refreshIndex).prefix(12))

        return HomeFeedSnapshot(
            featuredArtist: featuredArtist,
            featuredConcert: featuredConcert,
            forYouPicks: refreshedForYou,
            trendingArtists: trendingArtists,
            refreshedAt: date
        )
    }

    private static func rotated<T>(_ items: [T], by offset: Int) -> [T] {
        guard !items.isEmpty else { return items }
        let normalizedOffset = offset % items.count
        guard normalizedOffset != 0 else { return items }
        return Array(items[normalizedOffset...]) + Array(items[..<normalizedOffset])
    }

    private static func makeBillboardSampleArtist(name: String, source: String, year: Int, index: Int) -> Artist {
        let emojis = ["🎤", "🎧", "🎸", "🥁", "🎹"]
        let emoji = emojis[index % emojis.count]
        let isYearEndSource = source.contains("Top Artists 2024 #")
        let rank = source.split(separator: "#").last.map(String.init) ?? "?"
        let yearRange = isYearEndSource ? "Year-end breakout • 2024" : "Catalog breakout • 2026"
        let recordTitle = isYearEndSource ? "\(year) Tour Search" : "\(year) Archive Tour"
        let archiveVenue = "YouTube"
        let archiveDate = isYearEndSource ? "Tour search seeded from 2024 rank #\(rank)" : "Tour search seeded from January 2026 catalog"
        let archiveURL = makeYouTubeSearchURL("\(name) \(recordTitle)")

        return Artist(
            name: name,
            emoji: emoji,
            totalConcerts: 1,
            yearRange: yearRange,
            concerts: [
                Concert(
                    tourName: recordTitle,
                    year: year,
                    venue: archiveVenue,
                    city: "Canada",
                    date: archiveDate,
                    clipCount: 1,
                    rating: 4.0,
                    genres: ["Billboard", "Chart"],
                    clips: [
                        Clip(
                            songTitle: "Top track",
                            duration: "Live",
                            source: .youtube,
                            videoURL: archiveURL
                        )
                    ]
                )
            ]
        )
    }

    static var featured: Artist? { all.first(where: { $0.name == "Drake" }) }
}

// ── MARK: App State ───────────────────────────────────────────

@MainActor
class AppState: ObservableObject {
    @Published var queue: [PlayerTrack]
    @Published var currentTrack: PlayerTrack?
    @Published var isPlaying = false
    @Published var isLoadingTrack = false
    @Published var playerMessage = "Select a track and tap Play"
    @Published var currentFullTrackURL: URL?
    @Published var uploads: [UploadedVideo]

    private let player = AVPlayer()
    private var currentPreviewURL: URL?
    private var didConfigureAudioSession = false

    init() {
        let tracks = Artist.libraryTracks
        queue = tracks
        currentTrack = tracks.first
        uploads = VideoUploadStore.loadUploads()
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.allowsExternalPlayback = true
    }

    func play(track: PlayerTrack) {
        currentTrack = track
        currentFullTrackURL = track.clip.videoURL
        isLoadingTrack = true
        playerMessage = "Looking up track..."
        configureAudioSessionIfNeeded()

        Task {
            let lookup = await AudioPreviewService.shared.lookup(for: track)
            await MainActor.run {
                isLoadingTrack = false
                currentFullTrackURL = lookup?.fullTrackURL ?? track.clip.videoURL

                guard let previewURL = lookup?.previewURL else {
                    currentPreviewURL = nil
                    isPlaying = false
                    player.pause()
                    playerMessage = currentFullTrackURL == nil
                        ? "No playable source found for this track"
                        : "Full song available below"
                    return
                }

                currentPreviewURL = previewURL
                player.replaceCurrentItem(with: AVPlayerItem(url: previewURL))
                player.play()
                isPlaying = true
                playerMessage = currentFullTrackURL == nil
                    ? "Previewing track"
                    : "Previewing track. Full song available below"
            }
        }
    }

    func play(concert: Concert, artist: Artist) {
        guard let firstClip = concert.clips.first else { return }
        play(track: PlayerTrack(artist: artist, concert: concert, clip: firstClip))
    }

    func enqueue(concert: Concert, artist: Artist) {
        let tracks = concert.clips.map { clip in
            PlayerTrack(artist: artist, concert: concert, clip: clip)
        }

        for track in tracks where !queue.contains(where: { queuedTrack in
            queuedTrack.artist.name == track.artist.name &&
            queuedTrack.concert.id == track.concert.id &&
            queuedTrack.clip.id == track.clip.id
        }) {
            queue.append(track)
        }

        if currentTrack == nil {
            currentTrack = queue.first
        }
    }

    func togglePlayback() {
        guard currentPreviewURL != nil else {
            if let currentTrack {
                play(track: currentTrack)
            }
            return
        }
        configureAudioSessionIfNeeded()

        if isPlaying {
            player.pause()
            isPlaying = false
            playerMessage = currentFullTrackURL == nil ? "Paused" : "Preview paused. Full song available below"
        } else {
            player.play()
            isPlaying = true
            playerMessage = currentFullTrackURL == nil
                ? "Previewing track"
                : "Previewing track. Full song available below"
        }
    }

    func playNext() {
        guard !queue.isEmpty else { return }

        if let currentTrack,
           let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) {
            let nextIndex = queue.index(after: currentIndex)
            if nextIndex < queue.endIndex {
                play(track: queue[nextIndex])
            } else if let firstTrack = queue.first {
                play(track: firstTrack)
            }
        } else {
            if let firstTrack = queue.first {
                play(track: firstTrack)
            }
        }
    }

    func refreshUploads() {
        uploads = VideoUploadStore.loadUploads()
    }

    func importVideo(from sourceURL: URL, title: String, artistName: String, tourName: String) throws {
        _ = try VideoUploadStore.importVideo(from: sourceURL, title: title, artistName: artistName, tourName: tourName)
        refreshUploads()
    }

    func deleteUpload(_ upload: UploadedVideo) throws {
        try VideoUploadStore.delete(upload)
        refreshUploads()
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
            didConfigureAudioSession = true
        } catch {
            playerMessage = "Audio session setup failed"
        }
    }
}

// ── MARK: Main Root ───────────────────────────────────────────

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @StateObject private var appState = AppState()
    @State private var showLaunchScreen = true
    @State private var didRunLaunchSequence = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.nomoBG.ignoresSafeArea()

            Group {
                switch selectedTab {
                case 0: HomeView()
                case 1: ExploreView()
                case 2: UploadView()
                case 3: PlayerView()
                case 4: ProfileView()
                default: HomeView()
                }
            }
            .environmentObject(appState)
            .opacity(showLaunchScreen ? 0 : 1)

            NOMATabBar(selectedTab: $selectedTab)
                .opacity(showLaunchScreen ? 0 : 1)
        }
        .overlay {
            if showLaunchScreen {
                AppLoadingView()
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            startLaunchSequenceIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                startLaunchSequenceIfNeeded()
            }
        }
    }

    private func startLaunchSequenceIfNeeded() {
        guard !didRunLaunchSequence else { return }
        didRunLaunchSequence = true

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) {
                    showLaunchScreen = false
                }
            }
        }
    }
}

// ── MARK: Components ──────────────────────────────────────────

struct NOMATabBar: View {
    @Binding var selectedTab: Int
    let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("safari.fill", "Explore"),
        ("arrow.up.circle.fill", "Upload"),
        ("music.note", "PLAYER"),
        ("person.fill", "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = i } }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: i == 2 ? 26 : 20))
                            .foregroundColor(selectedTab == i ? Color.nomoViolet : Color.nomoGray)
                        Text(tabs[i].label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(selectedTab == i ? Color.nomoViolet : Color.nomoGray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.bottom, 30)
        .background(Color.nomoCard.overlay(Rectangle().fill(Color.nomoMidGray).frame(height: 0.5), alignment: .top))
    }
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedArtist: Artist? = nil
    @State private var homeFeed = Artist.homeFeed()
    private let homeFeedTimer = Timer.publish(every: Artist.homeFeedRefreshInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nomoBG.ignoresSafeArea()
                GlowBlobs()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Hey, DK 👋").font(.system(size: 22, weight: .black, design: .rounded)).foregroundColor(.white)
                                Text("What did you miss? Updated \(homeFeed.refreshedAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 14)).foregroundColor(Color.nomoGray)
                            }
                            Spacer()
                            Circle().fill(Color.nomoPurple.opacity(0.2)).frame(width: 44, height: 44).overlay(Text("🎵"))
                        }
                        .padding(.horizontal, 20).padding(.top, 40)

                        SectionLabel(text: "FEATURED").padding(.horizontal, 20)
                        FeaturedBanner(artist: homeFeed.featuredArtist, concert: homeFeed.featuredConcert)
                            .padding(.horizontal, 20)
                            .onTapGesture { selectedArtist = homeFeed.featuredArtist }

                        SectionLabel(text: "FOR YOU").padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(homeFeed.forYouPicks) { recommendation in
                                    ForYouVideoCard(recommendation: recommendation)
                                        .onTapGesture { selectedArtist = recommendation.artist }
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        SectionLabel(text: "TRENDING THIS WEEK").padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(homeFeed.trendingArtists) { artist in
                                    TrendingCard(artist: artist).onTapGesture { selectedArtist = artist }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedArtist != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedArtist = nil
                    }
                }
            )) {
                if let artist = selectedArtist {
                    ArtistView(artist: artist)
                }
            }
            .onAppear {
                refreshHomeFeed()
            }
            .onReceive(homeFeedTimer) { refreshHomeFeed(at: $0) }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    refreshHomeFeed()
                }
            }
        }
    }

    private func refreshHomeFeed(at date: Date = .now) {
        withAnimation(.easeInOut(duration: 0.4)) {
            homeFeed = Artist.homeFeed(at: date)
        }
    }
}

struct FeaturedBanner: View {
    let artist: Artist
    let concert: Concert
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color.nomoPurple.opacity(0.6), Color.nomoBG], startPoint: .topTrailing, endPoint: .bottomLeading)).frame(height: 180)
            HStack(alignment: .bottom, spacing: 16) {
                ArtistAvatar(artist: artist, size: 94, cornerRadius: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name).font(.system(size: 24, weight: .black)).foregroundColor(.white)
                    ResolvedCatalogSubtitleView(
                        artistName: artist.name,
                        concert: concert,
                        fallback: "\(concert.tourName) • \(concert.year)",
                        font: .system(size: 14),
                        color: Color.nomoGlow,
                        lineLimit: 1
                    )
                }
            }
            .padding(20)
        }
    }
}

struct TrendingCard: View {
    let artist: Artist
    var body: some View {
        VStack(alignment: .leading) {
            ArtistAvatar(artist: artist, size: 120, cornerRadius: 14)
            Text(artist.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
        }
        .frame(width: 120)
    }
}

struct ArtistAvatar: View {
    let artist: Artist
    let size: CGFloat
    let cornerRadius: CGFloat
    @State private var remoteImageURL: URL?

    var body: some View {
        Group {
            if let image = UIImage(named: artist.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteImageURL {
                AsyncImage(url: remoteImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholder
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .task(id: artist.name) {
            guard UIImage(named: artist.assetName) == nil else { return }
            if let overrideURL = artist.remoteImageOverrideURL {
                remoteImageURL = overrideURL
            } else {
                remoteImageURL = await ArtistImageService.shared.imageURL(for: artist.remoteImageLookupName)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.nomoCard)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.38))
                .foregroundColor(Color.nomoGray)
        }
    }
}

struct ForYouVideoCard: View {
    let recommendation: ForYouRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [recommendation.accent.opacity(0.85), Color.nomoCard],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 220, height: 160)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("FOR YOU")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white.opacity(0.85))
                            .tracking(1.2)
                        Spacer()
                        Image(systemName: recommendation.clip.source.rawValue)
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    HStack(alignment: .bottom) {
                        ArtistAvatar(artist: recommendation.artist, size: 52, cornerRadius: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            ResolvedTrackTitleView(
                                artistName: recommendation.artist.name,
                                clip: recommendation.clip,
                                font: .system(size: 18, weight: .black),
                                color: .white,
                                lineLimit: 2
                            )
                            Text("\(recommendation.artist.name) • \(recommendation.concert.year)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                    }
                }
                .padding(16)
            }

            Text(recommendation.reason)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.nomoGlow)
                .lineLimit(1)

            Text(recommendation.concert.tourName)
                .font(.system(size: 12))
                .foregroundColor(Color.nomoGray)
                .lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
    }
}

struct EmbeddedMediaView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

struct ResolvedTrackTitleView: View {
    let artistName: String
    let clip: Clip
    let font: Font
    let color: Color
    let lineLimit: Int?
    @State private var resolvedTitle: String?

    private var needsResolution: Bool {
        clip.songTitle == "Top track"
    }

    private var displayedTitle: String {
        if needsResolution {
            return resolvedTitle ?? "Loading top song..."
        }

        return clip.songTitle
    }

    var body: some View {
        Text(displayedTitle)
            .font(font)
            .foregroundColor(color)
            .lineLimit(lineLimit)
            .task(id: artistName) {
                guard needsResolution else { return }
                resolvedTitle = await CatalogTrackInfoService.shared.trackInfo(for: artistName)?.title ?? clip.songTitle
            }
    }
}

struct ResolvedConcertTitleView: View {
    let artistName: String
    let concert: Concert
    let font: Font
    let color: Color
    let lineLimit: Int?
    @State private var resolvedTitle: String?

    var body: some View {
        Text(resolvedTitle ?? concert.tourName)
            .font(font)
            .foregroundColor(color)
            .lineLimit(lineLimit)
            .task(id: artistName) {
                guard concert.isChartRecord else { return }
                resolvedTitle = await CatalogTrackInfoService.shared.trackInfo(for: artistName)?.title
            }
    }
}

struct ResolvedCatalogSubtitleView: View {
    let artistName: String
    let concert: Concert
    let fallback: String
    let font: Font
    let color: Color
    let lineLimit: Int?
    @State private var resolvedSubtitle: String?

    var body: some View {
        Text(resolvedSubtitle ?? fallback)
            .font(font)
            .foregroundColor(color)
            .lineLimit(lineLimit)
            .task(id: artistName) {
                guard concert.isChartRecord else { return }
                if let info = await CatalogTrackInfoService.shared.trackInfo(for: artistName) {
                    let parts = [info.album, info.year].compactMap { $0 }.filter { !$0.isEmpty }
                    if !parts.isEmpty {
                        resolvedSubtitle = parts.joined(separator: " • ")
                    }
                }
            }
    }
}

struct ArtistView: View {
    let artist: Artist
    var initialConcert: Concert? = nil
    var initialClip: Clip? = nil
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedConcert: Concert? = nil

    var body: some View {
        ZStack {
            Color.nomoBG.ignoresSafeArea()
            VStack(alignment: .leading) {
                Button("← Back") { dismiss() }.padding().foregroundColor(Color.nomoViolet)
                
                HStack(spacing: 16) {
                    ArtistAvatar(artist: artist, size: 80, cornerRadius: 40)
                    VStack(alignment: .leading) {
                        Text(artist.name).font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                        Text(artist.archiveSummary).foregroundColor(Color.nomoGray)
                    }
                }.padding(.horizontal)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(artist.concerts) { concert in
                            ArtistConcertRow(artist: artist, concert: concert).onTapGesture { selectedConcert = concert }
                        }
                    }.padding()
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedConcert) { concert in
            ConcertDetailView(artist: artist, concert: concert, initialClip: initialClip)
        }
        .onAppear {
            if let initialConcert, selectedConcert == nil {
                selectedConcert = initialConcert
            }
        }
    }
}

struct ArtistConcertRow: View {
    let artist: Artist
    let concert: Concert
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                ResolvedConcertTitleView(
                    artistName: artist.name,
                    concert: concert,
                    font: .body.weight(.bold),
                    color: .white,
                    lineLimit: 1
                )
                ResolvedCatalogSubtitleView(
                    artistName: artist.name,
                    concert: concert,
                    fallback: concert.rowSummary,
                    font: .caption,
                    color: .gray,
                    lineLimit: 1
                )
            }
            Spacer()
            Image(systemName: "play.circle.fill").font(.title2).foregroundColor(Color.nomoViolet)
        }
        .padding().background(Color.nomoCard).cornerRadius(12)
    }
}

struct ConcertDetailView: View {
    let artist: Artist
    let concert: Concert
    var initialClip: Clip? = nil
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedClip: Clip?
    
    var body: some View {
        ZStack {
            Color.nomoBG.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Close") { dismiss() }.foregroundColor(.white)
                    Spacer()
                    Button(action: { appState.enqueue(concert: concert, artist: artist) }) {
                        Image(systemName: "music.note.list").foregroundColor(.pink)
                    }
                }.padding()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.nomoCard)

                    if let playbackURL = selectedClip?.videoURL ?? concert.clips.first?.videoURL {
                        EmbeddedMediaView(url: playbackURL)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: concert.isChartRecord ? "chart.xyaxis.line" : "video.slash")
                                .font(.system(size: 28))
                                .foregroundColor(Color.nomoGray)
                            Text(concert.detailHeadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(height: 220)
                
                ResolvedConcertTitleView(
                    artistName: artist.name,
                    concert: concert,
                    font: .title2.weight(.bold),
                    color: .white,
                    lineLimit: 2
                )
                ResolvedCatalogSubtitleView(
                    artistName: artist.name,
                    concert: concert,
                    fallback: concert.detailSubheadline,
                    font: .body,
                    color: .gray,
                    lineLimit: 2
                )
                
                List(concert.clips) { clip in
                    Button {
                        selectedClip = clip
                        appState.play(track: PlayerTrack(artist: artist, concert: concert, clip: clip))
                    } label: {
                        HStack {
                            Image(systemName: "play.fill").foregroundColor(Color.nomoViolet)
                            ResolvedTrackTitleView(
                                artistName: artist.name,
                                clip: clip,
                                font: .body,
                                color: .white,
                                lineLimit: 1
                            )
                            Spacer()
                            Text(clip.duration).font(.caption).foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.nomoCard)
                }.listStyle(.plain)
            }
        }
        .onAppear {
            if let initialClip,
               concert.clips.contains(where: { $0.id == initialClip.id }) {
                selectedClip = initialClip
            } else {
                selectedClip = concert.clips.first
            }
        }
    }
}

struct UploadView: View {
    @EnvironmentObject var appState: AppState
    @State private var isImporterPresented = false
    @State private var selectedFileURL: URL?
    @State private var clipTitle = ""
    @State private var artistName = ""
    @State private var tourName = ""
    @State private var statusMessage = "Import a video file from Files."
    @State private var selectedUpload: UploadedVideo?

    private var canSubmit: Bool {
        selectedFileURL != nil &&
        !clipTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tourName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Upload a Clip")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            isImporterPresented = true
                        } label: {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.nomoMidGray, style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .frame(height: 170)
                                .overlay {
                                    VStack(spacing: 10) {
                                        Image(systemName: "video.badge.plus")
                                            .font(.system(size: 34, weight: .bold))
                                            .foregroundColor(Color.nomoGlow)
                                        Text(selectedFileURL?.lastPathComponent ?? "Pick a video file")
                                            .font(.headline.weight(.semibold))
                                            .foregroundColor(.white)
                                        Text("MOV, MP4, M4V and other movie files")
                                            .font(.caption)
                                            .foregroundColor(Color.nomoGray)
                                    }
                                    .padding()
                                }
                        }
                        .buttonStyle(.plain)

                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(Color.nomoGray)

                        UploadInputField(title: "Clip title", text: $clipTitle, placeholder: "Carnival live intro")
                        UploadInputField(title: "Artist", text: $artistName, placeholder: "Kanye West")
                        UploadInputField(title: "Tour", text: $tourName, placeholder: "Donda Tour")

                        Button {
                            submitUpload()
                        } label: {
                            Text("Save Video")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: canSubmit ? [Color.nomoViolet, Color.nomoPink] : [Color.nomoMidGray, Color.nomoMidGray],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                    .background(Color.nomoCard)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel(text: "YOUR UPLOADS")
                            Spacer()
                            Text("\(appState.uploads.count)")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                        }

                        if appState.uploads.isEmpty {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.nomoCard)
                                .frame(height: 160)
                                .overlay {
                                    VStack(spacing: 8) {
                                        Image(systemName: "film.stack")
                                            .font(.title)
                                            .foregroundColor(Color.nomoGlow)
                                        Text("No uploads yet")
                                            .foregroundColor(.white)
                                        Text("Imported videos will live here and play back inside the app.")
                                            .font(.caption)
                                            .foregroundColor(Color.nomoGray)
                                    }
                                }
                        } else {
                            ForEach(appState.uploads) { upload in
                                Button {
                                    selectedUpload = upload
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.nomoPurple.opacity(0.8), Color.nomoPink.opacity(0.85)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 88, height: 88)
                                            Image(systemName: "play.rectangle.fill")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(upload.title)
                                                .font(.headline.weight(.semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                            Text(upload.displaySubtitle)
                                                .font(.subheadline)
                                                .foregroundColor(Color.nomoGlow)
                                                .lineLimit(1)
                                            Text(upload.fileName)
                                                .font(.caption)
                                                .foregroundColor(Color.nomoGray)
                                                .lineLimit(1)
                                        }

                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Color.nomoGray)
                                    }
                                    .padding(16)
                                    .background(Color.nomoCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        try? appState.deleteUpload(upload)
                                    } label: {
                                        Label("Delete Upload", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.nomoBG.ignoresSafeArea())
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video]
            ) { result in
                switch result {
                case .success(let url):
                    selectedFileURL = url
                    statusMessage = "Ready to import \(url.lastPathComponent)"
                    if clipTitle.isEmpty {
                        clipTitle = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                    }
                case .failure(let error):
                    statusMessage = error.localizedDescription
                }
            }
            .sheet(item: $selectedUpload) { upload in
                UploadedVideoPlayerView(upload: upload)
            }
        }
    }

    private func submitUpload() {
        guard let selectedFileURL else { return }

        do {
            try appState.importVideo(
                from: selectedFileURL,
                title: clipTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                artistName: artistName.trimmingCharacters(in: .whitespacesAndNewlines),
                tourName: tourName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            statusMessage = "Saved \(clipTitle) to NOMO."
            self.selectedFileURL = nil
            clipTitle = ""
            artistName = ""
            tourName = ""
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct ExploreView: View {
    @State private var query = ""
    @State private var selectedArtist: Artist?

    private var filteredArtists: [Artist] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return Artist.all.filter { artist in
            artist.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            artist.yearRange.localizedCaseInsensitiveContains(trimmedQuery) ||
            artist.concerts.contains { concert in
                concert.tourName.localizedCaseInsensitiveContains(trimmedQuery) ||
                concert.venue.localizedCaseInsensitiveContains(trimmedQuery) ||
                concert.city.localizedCaseInsensitiveContains(trimmedQuery) ||
                concert.genres.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) })
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Search artists, tours, cities...", text: $query)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color.nomoCard)
                        .cornerRadius(10)
                        .foregroundColor(.white)

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trending Searches")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .tracking(1.2)

                            ForEach(Artist.all.prefix(5)) { artist in
                                Button {
                                    query = artist.name
                                } label: {
                                    HStack {
                                        ArtistAvatar(artist: artist, size: 36, cornerRadius: 18)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(artist.name)
                                                .foregroundColor(.white)
                                            Text(artist.discoverySummary)
                                                .font(.caption)
                                                .foregroundColor(Color.nomoGray)
                                        }
                                        Spacer()
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(Color.nomoGray)
                                    }
                                    .padding()
                                    .background(Color.nomoCard)
                                    .cornerRadius(14)
                                }
                            }
                        }
                    } else if filteredArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No results")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Try an artist name, tour, venue, or city.")
                                .foregroundColor(Color.nomoGray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.nomoCard)
                        .cornerRadius(14)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Results")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .tracking(1.2)

                            ForEach(filteredArtists) { artist in
                                Button {
                                    selectedArtist = artist
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtistAvatar(artist: artist, size: 48, cornerRadius: 16)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(artist.name)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Text(artist.resultSummary)
                                                .font(.caption)
                                                .foregroundColor(Color.nomoGray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Color.nomoGray)
                                    }
                                    .padding()
                                    .background(Color.nomoCard)
                                    .cornerRadius(14)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color.nomoBG.ignoresSafeArea())
            .navigationDestination(isPresented: Binding(
                get: { selectedArtist != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedArtist = nil
                    }
                }
            )) {
                if let artist = selectedArtist {
                    ArtistView(artist: artist)
                }
            }
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    @State private var showLoadingScreen = true
    @State private var didStartPlayerIntro = false
    @State private var artistPlaybackRoute: ArtistPlaybackRoute?

    private var upcomingTracks: [PlayerTrack] {
        guard let currentTrack else { return appState.queue }
        return appState.queue.filter { $0.id != currentTrack.id }
    }

    private var currentTrack: PlayerTrack? {
        appState.currentTrack
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.nomoBG, Color.nomoCard],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GlowBlobs()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PLAYER")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("NOMO playback")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color.nomoGray)
                        }
                        Spacer()
                        Text("LIVE")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.nomoPink, Color.nomoViolet],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }

                    if let currentTrack {
                        VStack(alignment: .leading, spacing: 20) {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.nomoCard, Color.nomoPurple.opacity(0.9)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 340)

                                VStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        PlayerStatusPill(
                                            text: appState.isLoadingTrack ? "BUFFERING" : (appState.isPlaying ? "PLAYING" : "READY"),
                                            accent: appState.isLoadingTrack ? .nomoGlow : .nomoPink
                                        )
                                        Spacer()
                                        if let sourceURL = appState.currentFullTrackURL ?? currentTrack.clip.videoURL {
                                            Button {
                                                openURL(sourceURL)
                                            } label: {
                                                Image(systemName: "safari.fill")
                                                    .font(.headline.weight(.bold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 40, height: 40)
                                                    .background(Color.white.opacity(0.14))
                                                    .clipShape(Circle())
                                            }
                                        }
                                    }

                                    Spacer()

                                    HStack(alignment: .bottom, spacing: 18) {
                                        ArtistAvatar(artist: currentTrack.artist, size: 132, cornerRadius: 34)
                                            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 18)

                                        VStack(alignment: .leading, spacing: 8) {
                                            ResolvedTrackTitleView(
                                                artistName: currentTrack.artist.name,
                                                clip: currentTrack.clip,
                                                font: .system(size: 30, weight: .heavy, design: .rounded),
                                                color: .white,
                                                lineLimit: 2
                                            )
                                            Text(currentTrack.artist.name.uppercased())
                                                .font(.caption.weight(.bold))
                                                .tracking(1.4)
                                                .foregroundColor(Color.nomoGlow)
                                            ResolvedCatalogSubtitleView(
                                                artistName: currentTrack.artist.name,
                                                concert: currentTrack.concert,
                                                fallback: currentTrack.concert.tourName,
                                                font: .subheadline.weight(.medium),
                                                color: Color.white.opacity(0.82),
                                                lineLimit: 2
                                            )
                                        }
                                    }
                                }
                                .padding(24)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text(appState.playerMessage)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(appState.isLoadingTrack ? Color.nomoGlow : Color.nomoGray)

                                if appState.isLoadingTrack {
                                    ProgressView()
                                        .tint(Color.nomoViolet)
                                }

                                HStack(spacing: 14) {
                                    PlayerActionButton(
                                        systemName: "music.note.tv",
                                        label: "Full Song",
                                        accent: .nomoPink
                                    ) {
                                        artistPlaybackRoute = ArtistPlaybackRoute(
                                            artist: currentTrack.artist,
                                            concert: currentTrack.concert,
                                            clip: currentTrack.clip
                                        )
                                    }

                                    PlayerActionButton(
                                        systemName: appState.isPlaying ? "pause.fill" : "play.fill",
                                        label: appState.isPlaying ? "Pause Preview" : "Play Preview",
                                        accent: .nomoViolet,
                                        filled: true
                                    ) {
                                        appState.togglePlayback()
                                    }
                                    .disabled(appState.isLoadingTrack)

                                    PlayerActionButton(
                                        systemName: "forward.fill",
                                        label: "Next",
                                        accent: .nomoGlow
                                    ) {
                                        appState.playNext()
                                    }
                                    .disabled(appState.isLoadingTrack)
                                }
                            }
                            .padding(20)
                            .background(Color.nomoCard.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(text: "FROM THE ARCHIVE")
                                HStack(spacing: 12) {
                                    PlayerMetaTile(title: "Artist", value: currentTrack.artist.name)
                                    PlayerMetaTile(title: "Tour", value: currentTrack.concert.tourName)
                                    PlayerMetaTile(title: "Source", value: currentTrack.concert.venue)
                                }
                            }
                        }
                    } else {
                        Text("No track selected")
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "UP NEXT")
                        ForEach(upcomingTracks) { track in
                            Button {
                                appState.play(track: track)
                            } label: {
                                HStack(spacing: 14) {
                                    ArtistAvatar(artist: track.artist, size: 58, cornerRadius: 18)
                                    VStack(alignment: .leading, spacing: 5) {
                                        ResolvedTrackTitleView(
                                            artistName: track.artist.name,
                                            clip: track.clip,
                                            font: .body.weight(.semibold),
                                            color: .white,
                                            lineLimit: 1
                                        )
                                        ResolvedCatalogSubtitleView(
                                            artistName: track.artist.name,
                                            concert: track.concert,
                                            fallback: "\(track.artist.name) • \(track.concert.tourName)",
                                            font: .caption,
                                            color: Color.nomoGray,
                                            lineLimit: 1
                                        )
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(Color.nomoViolet)
                                }
                                .padding(16)
                                .background(Color.nomoCard.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }
                }
                .padding()
            }
            .opacity(showLoadingScreen ? 0 : 1)

            if showLoadingScreen {
                PlayerLoadingView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard !didStartPlayerIntro else { return }
            didStartPlayerIntro = true

            Task {
                try? await Task.sleep(nanoseconds: 1_350_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showLoadingScreen = false
                    }
                }
            }
        }
        .sheet(item: $artistPlaybackRoute) { route in
            NavigationStack {
                ArtistView(
                    artist: route.artist,
                    initialConcert: route.concert,
                    initialClip: route.clip
                )
            }
            .presentationDragIndicator(.visible)
        }
    }
}

struct PlayerLoadingView: View {
    @State private var pulse = false

    var body: some View {
        NOMOLoadingView(
            title: "NOMO",
            subtitle: "Loading your player",
            systemImage: "music.note",
            gradientColors: [Color.black, Color.nomoBG, Color.nomoPurple.opacity(0.85)],
            pulse: $pulse
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct AppLoadingView: View {
    @State private var pulse = false

    var body: some View {
        NOMOLoadingView(
            title: "NOMO",
            subtitle: "Booting the archive",
            systemImage: "waveform.circle.fill",
            gradientColors: [Color.black, Color.nomoBG, Color.nomoPink.opacity(0.8)],
            pulse: $pulse
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct NOMOLoadingView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let gradientColors: [Color]
    @Binding var pulse: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GlowBlobs()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.04 : 0.92)
                    Circle()
                        .stroke(Color.nomoGlow.opacity(0.55), lineWidth: 2)
                        .frame(width: 156, height: 156)
                        .scaleEffect(pulse ? 1.08 : 0.95)
                    Image(systemName: systemImage)
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color.nomoGray)
                }
            }
        }
    }
}

struct PlayerStatusPill: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.1)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(accent.opacity(0.28))
            .clipShape(Capsule())
    }
}

struct PlayerActionButton: View {
    let systemName: String
    let label: String
    let accent: Color
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(filled ? AnyShapeStyle(LinearGradient(
                        colors: [accent, Color.nomoPink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )) : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(filled ? 0 : 0.45), lineWidth: 1)
            )
        }
    }
}

struct PlayerMetaTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundColor(Color.nomoGray)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nomoCard.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct UploadInputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundColor(Color.nomoGray)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding()
                .background(Color.black.opacity(0.22))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct UploadedVideoPlayerView: View {
    let upload: UploadedVideo
    @Environment(\.dismiss) var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)

                    Spacer()
                }

                VideoPlayer(player: player)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(upload.title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text(upload.displaySubtitle)
                    .foregroundColor(Color.nomoGlow)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: upload.fileURL))
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack {
            Circle().fill(Color.nomoPurple).frame(width: 100, height: 100).overlay(Text("DK").font(.title).bold())
            Text("@dk_music").foregroundColor(.gray)
            HStack(spacing: 40) {
                VStack { Text("\(appState.queue.count)").bold(); Text("Tracks").font(.caption) }
                VStack { Text("\(appState.uploads.count)").bold(); Text("Uploads").font(.caption) }
            }.padding().foregroundColor(.white)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.nomoBG)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(Color.nomoGray).tracking(1.5)
    }
}

struct GlowBlobs: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.nomoPurple.opacity(0.1)).frame(width: 300).offset(x: -100, y: -200).blur(radius: 50)
            Circle().fill(Color.nomoPink.opacity(0.1)).frame(width: 250).offset(x: 100, y: 200).blur(radius: 50)
        }.allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
}
