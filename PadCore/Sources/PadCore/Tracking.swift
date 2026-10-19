import Foundation

/// A page's address without what it carries to follow the reader by: the
/// tags an advertisement, a newsletter or a share button hangs on a link
/// (utm_source, fbclid, Naver's NaPm). They say where the reader came
/// from, not where the page is, and the address is going to someone
/// else: shared, copied, handed off (Handoff.prompt, Browser.sharePage).
public enum Tracking {
    /// The address with those tags taken out of its query, and nothing
    /// else changed. Names known to be that and nothing else, wherever
    /// they are; and on the sites whose own share buttons add tags of
    /// their own, those too, there alone (`perSite`): what is the site's
    /// way of following a share on one site is a page's own setting on
    /// another (`t` is a place in a video on YouTube, a share's token on X).
    public static func clean(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = parts.queryItems, !items.isEmpty else {
            return url
        }
        let own = siteTags(for: (parts.host ?? "").lowercased())
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if prefixes.contains(where: name.hasPrefix) || names.contains(name) { return false }
            return !own.contains(name)
        }
        guard kept.count != items.count else { return url }
        // As the address wrote what is kept: taken out of the query as it stands, not put together again.
        let keptNames = Set(kept.map(\.name))
        let query = (parts.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: true).filter { pair in
            let name = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            return keptNames.contains(name.removingPercentEncoding ?? name)
        }
        parts.percentEncodedQuery = query.isEmpty ? nil : query.joined(separator: "&")
        return parts.url ?? url
    }

    /// Whole families of tags, by how their names begin: Google's and
    /// everyone's campaign tags, and HubSpot's for its advertisements.
    private static let prefixes = ["utm_", "hsa_"]

    private static let names: Set<String> = [
        // Advertising networks' click ids.
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "gad_source", "gad_campaignid", "srsltid", "msclkid", "yclid",
        "twclid", "ttclid", "li_fat_id", "epik", "irclickid", "rb_clickid", "s_kwcid", "ef_id", "zanpid", "_openstat",
        // Share buttons and apps.
        "igshid", "igsh", "mibextid", "ref_src", "ref_url", "_branch_match_id",
        "fb_action_ids", "fb_action_types", "fb_ref", "fb_source", "action_object_map", "action_type_map", "action_ref_map",
        // Newsletters and the services that send them.
        "mc_cid", "mc_eid", "mkt_tok", "_hsenc", "_hsmi", "_kx", "vero_id", "oly_anon_id", "oly_enc_id", "ml_subscriber",
        "ml_subscriber_hash", "wickedid", "s_cid", "__s",
        // Analytics: Google's and Matomo's.
        "_ga", "_gl", "pk_campaign", "pk_kwd", "pk_keyword", "pk_source", "pk_medium", "pk_content", "pk_cid",
        "mtm_campaign", "mtm_kwd", "mtm_keyword", "mtm_source", "mtm_medium", "mtm_content", "mtm_cid", "mtm_group", "mtm_placement",
        // Naver's: where a visit to a shop came from, and the advertisement it came by.
        "napm", "nacn", "n_media", "n_query", "n_rank", "n_ad_group", "n_ad", "n_keyword_id", "n_keyword", "n_campaign_type",
        "n_ad_group_type", "n_match",
    ]

    /// What a site's own share links and apps add, by the site's domain
    /// (each covers its subdomains): who shared, from where, with what.
    private static let perSite: [(domains: [String], tags: Set<String>)] = [
        (["youtube.com", "youtu.be"], ["si", "pp", "ra", "feature", "app", "ab_channel"]),
        (["x.com", "twitter.com"], ["s", "t"]),
        (["tiktok.com"], ["_r", "_t", "is_from_webapp", "sender_device", "sender_web_id", "share_app_id", "share_link_id",
                          "share_item_id", "u_code", "tt_from"]),
        (["spotify.com"], ["si", "nd"]),
        (["linkedin.com"], ["trk", "trackingid", "refid", "lipi", "midtoken", "midsig", "trkemail"]),
        (["reddit.com"], ["share_id", "rdt", "ref_source"]),
    ]

    private static func siteTags(for host: String) -> Set<String> {
        guard !host.isEmpty else { return [] }
        return perSite.reduce(into: Set<String>()) { tags, site in
            if site.domains.contains(where: { Hosts.host(host, isWithin: $0) }) { tags.formUnion(site.tags) }
        }
    }
}
