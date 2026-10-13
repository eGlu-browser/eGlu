import Foundation

/// A filter list Safience can use: what it is called, what it takes away,
/// whose it is (shown in Settings, as its licence asks) and where it comes
/// from.
public struct FilterList: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// What the list calls itself in its "! Title:" line, which a download
    /// is checked against: its name, but for one that spells it another way.
    public let title: String
    /// What it takes away, in a few words, for Settings.
    public let about: String
    /// Whose it is and under which licence.
    public let credit: String
    public let url: URL
    /// A copy ships inside the app, so it blocks from the first launch, with
    /// no network. The others are downloaded when they are first turned on.
    public let bundled: Bool
    /// On unless turned off, whatever the device's language.
    public let onByDefault: Bool
    /// The languages (ISO 639) and regions (ISO 3166) whose sites it is
    /// for: on unless turned off where one of them is the device's.
    public let languages: [String]
    public let regions: [String]
    /// A real copy weighs at least this much, in bytes: less is an error
    /// page or half a download.
    public let leastSize: Int
}

extension ContentBlocking {
    private static let easyList = "the EasyList authors (easylist.to), CC BY-SA"

    private static func list(_ id: String, _ name: String, _ about: String, _ address: String, title: String? = nil,
                             credit: String = easyList, bundled: Bool = false, on: Bool = false,
                             languages: [String] = [], regions: [String] = [], least: Int = 20_000) -> FilterList? {
        URL(string: address).map {
            FilterList(id: id, name: name, title: title ?? name, about: about, credit: credit, url: $0, bundled: bundled,
                       onByDefault: on, languages: languages, regions: regions, leastSize: least)
        }
    }

    /// Every list there is to choose from, in the order Settings shows them
    /// and their rules go to WebKit: the best known first, by the stars its
    /// repository has on GitHub (counted on 13 October 2026, beside each
    /// below). EasyList, EasyPrivacy and the Cookie List are one repository;
    /// lists with the same count go by name.
    ///
    /// EasyList, EasyPrivacy and YousList ship in the app (Filters/LICENSE.md
    /// has their licences); the rest are downloaded from their authors when
    /// turned on. The EasyList authors license theirs under GPLv3 or CC BY-SA
    /// 3.0 or later, and Safience uses them under CC BY-SA.
    public static let lists: [FilterList] = [
        // easylist/easylist: 3,161
        list("easylist", "EasyList", "Ads", "https://easylist.to/easylist/easylist.txt",
             bundled: true, on: true, least: 100_000),
        list("easyprivacy", "EasyPrivacy", "Trackers", "https://easylist.to/easylist/easyprivacy.txt",
             bundled: true, on: true, least: 100_000),
        list("cookies", "EasyList Cookie List", "Cookie banners. A site that waits for an answer may stop working",
             "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt", title: "Easylist Cookie List",
             credit: "the EasyList authors and Fanboy (easylist.to), CC BY 3.0", least: 100_000),
        // easylist/easylistchina: 359
        list("easylistchina", "EasyList China", "Ads on Chinese sites",
             "https://easylist-downloads.adblockplus.org/easylistchina.txt", languages: ["zh"], regions: ["CN"]),
        // yous/YousList: 325
        list("youslist", "YousList", "Ads on Korean sites",
             "https://raw.githubusercontent.com/yous/YousList/master/youslist.txt",
             credit: "yous and contributors (github.com/yous/YousList), CC BY 4.0",
             bundled: true, on: true, least: 100_000),
        // easylist/antiadblockfilters: 72
        list("antiadblock", "Adblock Warning Removal List", "Notices that ask you to turn blocking off",
             "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt", on: true),
        // easylist/easylistgermany: 51
        list("easylistgermany", "EasyList Germany", "Ads on German sites",
             "https://easylist.to/easylistgermany/easylistgermany.txt", languages: ["de"], regions: ["DE", "AT", "CH"]),
        // easylist/listefr: 22
        list("liste_fr", "Liste FR", "Ads on French sites", "https://easylist-downloads.adblockplus.org/liste_fr.txt",
             credit: "the Liste FR authors (github.com/easylist/listefr), CC BY-SA 3.0",
             languages: ["fr"], regions: ["FR"]),
        // easylist/easylistspanish: 19
        list("easylistspanish", "EasyList Spanish", "Ads on Spanish sites",
             "https://easylist-downloads.adblockplus.org/easylistspanish.txt", languages: ["es"], regions: ["ES"]),
        // easylist/KoreanList: 13
        list("koreanlist", "KoreanList", "More ads on Korean sites",
             "https://easylist-downloads.adblockplus.org/koreanlist.txt", languages: ["ko"], regions: ["KR"]),
        // easylist/easylistitaly: 10
        list("easylistitaly", "EasyList Italy", "Ads on Italian sites",
             "https://easylist-downloads.adblockplus.org/easylistitaly.txt", languages: ["it"], regions: ["IT"]),
        // easylist/easylistportuguese: 10
        list("easylistportuguese", "EasyList Portuguese", "Ads on Portuguese sites",
             "https://easylist-downloads.adblockplus.org/easylistportuguese.txt", languages: ["pt"], regions: ["PT", "BR"]),
        // easylist/easylistdutch: 4
        list("easylistdutch", "EasyList Dutch", "Ads on Dutch sites",
             "https://easylist-downloads.adblockplus.org/easylistdutch.txt", languages: ["nl"], regions: ["NL"]),
    ].compactMap { $0 }

    /// The languages in a device's list of them ("ko-KR", "zh-Hans-CN"), as
    /// the lists name theirs ("ko", "zh").
    public static func languages(of preferred: [String]) -> [String] {
        var out: [String] = []
        for language in preferred {
            guard let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased(),
                  !code.isEmpty, !out.contains(code) else { continue }
            out.append(code)
        }
        return out
    }

    /// Whether a list is on where nothing was chosen: the ones for everyone,
    /// and the one for the device's language or region.
    public static func isOnByDefault(_ list: FilterList, languages: [String], region: String?) -> Bool {
        if list.onByDefault { return true }
        if list.languages.contains(where: languages.contains) { return true }
        if let region, list.regions.contains(region.uppercased()) { return true }
        return false
    }
}

extension Preferences {
    /// Whether a list is used: as chosen in Settings, or as it starts out.
    public func uses(_ list: FilterList, languages: [String], region: String?) -> Bool {
        filterLists[list.id] ?? ContentBlocking.isOnByDefault(list, languages: languages, region: region)
    }

    /// The lists in use, in the catalogue's order.
    public func filterLists(languages: [String], region: String?) -> [FilterList] {
        ContentBlocking.lists.filter { uses($0, languages: languages, region: region) }
    }
}
