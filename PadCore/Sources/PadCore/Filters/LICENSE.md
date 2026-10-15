# The filter lists

Three lists ship in this folder, each copied unchanged from its authors. The app turns them into WebKit's content-blocking rules on the device (`ContentBlocking.swift`), and into rules for the scripts it gives a site's pages (`ScriptedFilters.swift`); those are adaptations of the lists and are under the same licences. Safience's own code is not part of the lists and is not covered by them.

## EasyList and EasyPrivacy

`easylist.txt` and `easyprivacy.txt` are EasyList and EasyPrivacy, by the EasyList authors (https://easylist.to/), copied from https://easylist.to/easylist/ on the date in each file's `! Last modified:` line.

The EasyList authors dual-license them under the GNU General Public License version 3 or later, and under Creative Commons Attribution-ShareAlike 3.0 Unported or later (https://easylist.to/pages/licence.html). Safience uses them under Creative Commons Attribution-ShareAlike (https://creativecommons.org/licenses/by-sa/4.0/).

## YousList

`youslist.txt` is YousList, by yous and its contributors (https://github.com/yous/YousList), copied from https://raw.githubusercontent.com/yous/YousList/master/youslist.txt at the version in its `! Version:` line.

Its content is licensed under Creative Commons Attribution 4.0 International (https://creativecommons.org/licenses/by/4.0/).

## Lists that do not ship

The other lists in Settings › Ads and trackers › Filter lists (`FilterLists.swift`) are not in the app: it downloads each from its authors when the list is turned on, and names its authors and licence beside it. They are KoreanList, the Adblock Warning Removal List, and the EasyList supplements for German, Chinese, Italian, Dutch, Spanish and Portuguese sites (the EasyList authors, same licences as EasyList); Liste FR (its authors, CC BY-SA 3.0); and the EasyList Cookie List (the EasyList authors and Fanboy, CC BY 3.0).

## Updates

The app downloads newer copies of the lists in use from their authors no more than once every four days, whatever shorter time a list's `! Expires:` line gives.
