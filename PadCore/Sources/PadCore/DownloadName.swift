import Foundation

/// The name a download is saved under: the site's name for the file, a
/// name only, never a path it wrote into it; " 2", " 3" before the
/// extension when the name is taken, as Safari does. Taken means a file
/// there already, or another download still going that was given the name
/// before its file exists.
public enum DownloadName {
    public static func free(for suggested: String, taken: (String) -> Bool) -> String {
        let given = (suggested as NSString).lastPathComponent
        let name = given.isEmpty || given == "/" || given == "." || given == ".." ? "Download" : given
        let base = (name as NSString).deletingPathExtension
        let ending = (name as NSString).pathExtension
        var candidate = name
        var count = 2
        while taken(candidate) {
            candidate = ending.isEmpty ? "\(base) \(count)" : "\(base) \(count).\(ending)"
            count += 1
        }
        return candidate
    }
}
