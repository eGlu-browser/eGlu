import Combine
import GameController
import PadCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// The tab a sideways drag on the phone bar brings in: from the right (1)
/// or the left (-1), and whether the bar will say its name or its address.
struct SlideNeighbour: Equatable {
    let tab: TabRecord
    let side: CGFloat
    let titled: Bool
}

/// How far the page on screen has loaded. Kept apart from the window's
/// model: a load says so dozens of times, and only the loading line needs
/// to hear each one.
@MainActor
final class LoadProgress: ObservableObject {
    @Published var fraction = 0.0
}

/// A sideways drag on the phone bar (Browser.slidBar): how far the address
/// has gone with the finger, and the tab coming in beside it. Kept apart
/// from the window's model: it changes with every move of the finger, and
/// only the bar's address row follows it.
@MainActor
final class BarSlide: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var coming: SlideNeighbour?
}

/// The side the system's vertical bar stands on, on the iPhone Duo.
enum StripEdge: Equatable {
    case leading
    case trailing

    /// The side the traits name; nil where there is no vertical bar (every
    /// device before iOS 27.1, every iPhone and iPad, the Duo open upright).
    init?(of traits: UITraitCollection) {
        guard #available(iOS 27.1, *) else { return nil }
        switch traits.verticalBarEdge {
        case .leading: self = .leading
        case .trailing: self = .trailing
        default: return nil
        }
    }
}

/// What a window's bars show, kept up to date from its page.
@MainActor
final class WindowModel: ObservableObject {
    @Published var spaceID: UUID
    @Published var tabID: UUID?
    @Published var url: URL?
    @Published var title = ""
    @Published var loading = false
    let load = LoadProgress()
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var secure = false
    @Published var signIn = false
    /// The address must show, whatever Settings says: a sign-in page, a page
    /// that failed, a new tab (AddressVisibility).
    @Published var addressRequired = false
    /// The tab on screen along the top says where it is rather than what it
    /// is called (Settings, and always on a sign-in page).
    @Published var showsAddress = false
    @Published var editingAddress = false
    /// A phone's bar has made room for the keyboard: only the address, over
    /// it. True with editingAddress but for the keyboard's first coming in a
    /// run of the app, when the bar waits for it (Browser.keyboardHasStarted)
    /// and keeps its tools until then.
    @Published var barRidesKeyboard = false
    /// Counts the turns at the address field: each one starts the field
    /// over, a second ⌘T while it is already open included, which
    /// editingAddress alone, true before and after, would not say.
    @Published var addressTurn = 0
    /// What was typed in one field, for the other to start from: the window
    /// changed layout while it was typed (Browser.refreshChrome). Taken, and
    /// cleared, by the field that begins next.
    var carriedAddress: String?
    /// The address field was opened to list everything (a new tab, or
    /// Command.everything): it starts empty, over every tab, space, command
    /// and setting, where it otherwise starts with the page's address and
    /// nothing under it.
    @Published var listsEverything = false
    /// What the address bar offers under the address being typed.
    let suggestions = Suggestions()
    @Published var banner: Banner?
    /// The colour along the top of the page, which the bars take on.
    @Published var siteColor: SiteColor?
    /// The colour under a phone's bar, which that bar and the rows over it
    /// take on; nil where the page has none to give (a new tab).
    @Published var footColor: SiteColor?
    /// The page is one of the space's bookmarks (the star in the address).
    @Published var bookmarked = false
    /// A phone-width window: the bars at the bottom, as on an iPhone (PhoneBar).
    @Published var phone = false
    /// A phone-width window with the system's vertical bar beside it, the
    /// side it stands on: the iPhone Duo closed, or one of two apps side by
    /// side on it (Docs/iPhoneDuoDesign.md §3). Nil anywhere else.
    @Published var strip: StripEdge?
    /// The window can open another (Device.makesWindows): New Window and
    /// Open in New Window show only where it can.
    @Published var makesWindows = false
    /// The page on screen is its mobile site (SiteMode).
    @Published var mobileSite = false
    /// The page is in the iPhone's desktop view (DesktopPad), or could be.
    @Published var desktopView = false
    @Published var canDesktopView = false
    /// Handoff is on in Settings and the page on screen can be handed off:
    /// it has an address, and it is not a hands-off page.
    @Published var canHandoff = false
    /// Ads and trackers blocked on the page on screen: true or false where
    /// its site's switch applies, nil where it doesn't (no page, a hands-off
    /// page, blocking off in Settings).
    @Published var blocking: Bool?
    /// The site on screen keeps its own context menus, the app's link menu
    /// off there (OwnMenus); nil where there is no site to say it of.
    @Published var ownMenus: Bool?
    let slide = BarSlide()

    init(spaceID: UUID) {
        self.spaceID = spaceID
    }

    /// Sets a value only when it is another. A page says the same things
    /// many times over as it loads, and an assignment, changed or not,
    /// draws again whatever watches the model.
    func set<Value: Equatable>(_ path: ReferenceWritableKeyPath<WindowModel, Value>, to value: Value) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }

    /// The page, or something on it, came over a connection anyone on the
    /// way can read. An http address says so at once; for the rest, WebKit
    /// knows only once the page has loaded, so a page still loading isn't
    /// marked, rather than marked and then unmarked a moment later.
    /// The words, when the page is a search with the chosen engine: the
    /// address shows them in its place (Destination.searchWords).
    var searchWords: String? {
        url.flatMap { Destination.searchWords(in: $0, engine: Session.shared.preferences.engine) }
    }

    var insecure: Bool {
        guard let url else { return false }
        return url.scheme?.lowercased() == "http" || (!loading && !secure)
    }
}

/// A line under the address bar that something needs saying.
enum Banner: Equatable {
    /// Google refused to sign in here (SignIn.googleRefused).
    case googleRefused
    /// The page's process kept ending (CrashGuard).
    case exhausted
    case failed(String)
}

/// One window: a row of tabs, an address bar when it is wanted, and a page.
///
/// The page gets everything it can: the window's whole width, the trackpad
/// (Pointer), the keys (PageView, Menus), the focus whenever the window
/// becomes active. The browser's own shortcuts are ⌃⌥ ones (Menus), out of
/// the way of any page's, but for the keys every browser keeps (⌘T and the like).
@MainActor
final class Browser: UIViewController, PageHost, UIAdaptivePresentationControllerDelegate, UIDocumentPickerDelegate,
    UIGestureRecognizerDelegate {
    let model: WindowModel
    /// The page on screen; with two side by side, the one with the keys,
    /// which the bars show and act on.
    private(set) var page: Page?
    /// The other pane, when the tab on screen is split with another tab.
    private(set) var partner: Page?
    private var firstTab: UUID?
    private var connected = true

    private let stack = UIStackView()
    private let stage = Stage()
    private let picture = UIImageView()
    private let partnerPicture = UIImageView()
    private let divider = SplitDivider()
    /// A line along the top of the pane with the keys, while there are two.
    private let focusEdge = UIView()
    /// Where the divider is while it is dragged, before the workspace hears.
    private var dragRatio: Double?
    private var topBar: UIHostingController<TopBar>?
    /// The tabs down the window's side, in place of the row along the top
    /// and the address bar (Settings › Tabs), and the stack's start beside
    /// it or at the window's edge.
    private var sideTabs: UIHostingController<SideTabs>?
    private var stackAtEdge: NSLayoutConstraint?
    private var stackBeside: NSLayoutConstraint?
    /// The sidebar's width: its own, or as far as the iPhone Duo's fold (placeSidebar).
    private var sideWidth: NSLayoutConstraint?
    /// While the sidebar shows, the window is the Mac's: the page a card a
    /// bezel in from the window's edges and from the sidebar, with round
    /// corners and a soft shadow, standing on the space's colour (the
    /// window's ground, WindowGround) as the sidebar does.
    private var carded = false
    /// The space's colour the window's views were last given (SpaceColorTrait).
    private var shownColour: SpaceColor?
    private var windowGround: UIHostingController<WindowGround>?
    private var stackTop: NSLayoutConstraint?
    private var stackTrailing: NSLayoutConstraint?
    /// The card's shadows, as the Mac's: a soft one under it and a tight one
    /// at its edge, each a view of its own behind the page, which is cut to its corners.
    private let cardShadow = UIView()
    private let cardEdge = UIView()
    private var phoneBar: UIHostingController<PhoneBar>?
    /// The iPhone Duo strip's tools, made the first time the window has a strip (showStrip).
    private var stripItems: StripItems?
    /// The phone bar's height: shorter while an address is typed (PhoneBar.typingHeight).
    private var phoneHeight: NSLayoutConstraint?
    /// The cursor and the trackpad over a page in the iPhone's desktop view.
    private var desktopPad: DesktopPad?
    /// The last tab a ⌘-click opened behind, and the tab it came from.
    private var openedBehind: (from: UUID, opened: UUID)?
    /// Whether the page on screen is bookmarked, as last worked out, and
    /// what it was worked out from (refreshChrome).
    private var starCheck: (url: URL?, bookmarks: [Bookmark], found: Bool)?
    private weak var barSwipe: BarSwipe?
    /// What the bar's swipe is doing: nothing; drawing the tabs up out of
    /// it; sliding the page to the tab beside; or, let go, that slide
    /// settling by itself, which a new sideways swipe can catch. One at a
    /// time: the tabs don't come up over a page between two tabs.
    private enum BarGesture { case idle, tabs, sliding, settling }
    private var barGesture = BarGesture.idle
    /// The page coming in beside the one on screen while the bar is dragged
    /// sideways, and the side it is on.
    private var slideCard: SlideCard?
    private var slideSide: CGFloat = 0
    /// Where a caught slide's page stood when a finger took it again: the drag goes on from there.
    private var slideBase: CGFloat = 0
    /// The settling slide's end, for a finger that catches it (catchSlide),
    /// and its count, so the spring's own ending is ignored once caught.
    private var settling: (target: CGFloat, goes: TabRecord?, count: Int) = (0, nil, 0)
    /// A tap as the drag crosses the line past which letting go goes to the tab beside.
    private var slideTicked = false
    private let slideTick = UIImpactFeedbackGenerator(style: .medium)
    /// Between two pages side by side, as between Safari's.
    private static let slideGap: CGFloat = 16
    /// The phone's tabs, while they show or the bar is turning into them.
    private var tabSheet: TabSheet?
    /// What the tabs were left for, done once they have gone: a new tab's
    /// typing waits for the bar to be back.
    private var afterTabs: BarAction?
    /// The stack's bottom: the safe area's on iPad; on a phone the screen's,
    /// so the page runs on under the bar and the home indicator.
    private var safeBottom: NSLayoutConstraint?
    private var screenBottom: NSLayoutConstraint?
    /// The phone bar's bottom: the safe area's, or the keyboard's while an
    /// address is typed.
    private var barSafeBottom: NSLayoutConstraint?
    private var barKeyboardBottom: NSLayoutConstraint?
    /// Behind the phone bar: the page through it, blurred more the lower it is (BarBackdrop).
    private let barBackdrop = BarBackdrop()
    private var addressBar: UIHostingController<AddressBar>?
    /// The space's bookmarks under the bars, where the tabs are along the top (BookmarksStrip).
    private var bookmarksStrip: UIHostingController<BookmarksStrip>?
    private var bannerBar: UIHostingController<BannerBar>?
    private var empty: UIHostingController<EmptySpace>?
    private var start: UIHostingController<StartPage>?
    private var diagnostics: UIHostingController<DiagnosticsView>?
    /// The hinge, heard while the diagnostics panel shows (iPhone Duo).
    private var hingeWatch: UIInteraction?
    /// The address bar's suggestions on a phone, over the bar
    /// (placeSuggestions). On iPad they are part of the command bar.
    private var suggestionList: UIHostingController<SuggestionList>?
    private var suggestionHeight: NSLayoutConstraint?
    /// The handoff under way, from Handoff being asked for until its share
    /// sheet closes (handoff), and the model asked what kind of page it is:
    /// the browser's own, made when the first handoff is.
    private var handingOff: HandoffJob?
    /// A handoff was asked for and is not yet on screen: a second ask meanwhile is the same one.
    private var startsHandoff = false
    /// What to do if the handoff's guide is put away without a button.
    private var guideClosed: (() -> Void)?

    /// The command bar, on iPad: the address field and its rows, floating
    /// over the page while an address is typed (placeCommandBar).
    private var commandBar: UIHostingController<CommandBar>?
    private var commandBarTop: NSLayoutConstraint?
    private var commandBarShown = false
    /// The new tab the command bar is open for (⌘T, +) and the tab it was
    /// opened from, until typing ends: the new tab goes again if the row
    /// taken wasn't an address for it (leave).
    private var madeForBar: MadeTab?

    /// A tab made to type an address in, and where the window was before.
    struct MadeTab {
        let tab: UUID
        let from: UUID?
    }
    private var subscriptions: Set<AnyCancellable> = []

    var isConnected: Bool { connected }

    /// The tabs this window has on screen: one, or a split's two.
    var shownTabs: [UUID] {
        [model.tabID, partner?.tab].compactMap { $0 }
    }

    func shows(_ tab: UUID) -> Bool {
        model.tabID == tab || partner?.tab == tab
    }

    init(state: WindowState) {
        let workspace = Session.shared.workspace
        let space = state.space.flatMap { workspace.space($0) } ?? workspace.firstSpace
        model = WindowModel(spaceID: space.id)
        // The tab the window had, if the space still has it: one closed since
        // (the system keeps a window's state a while behind) would leave
        // the window showing nothing, with tabs to show.
        firstTab = state.tab.flatMap { workspace.tab($0) == nil ? nil : $0 } ?? space.selected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var state: WindowState {
        WindowState(space: model.spaceID, tab: model.tabID)
    }

    override func loadView() {
        let root = BrowserView()
        root.constraintsUpdated = { [weak self] in self?.placeSidebar(animated: true) }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.UI.ground
        Session.shared.register(self)
        build()
        Session.shared.$workspace
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.workspaceChanged() }
            .store(in: &subscriptions)
        Session.shared.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshChrome() }
            .store(in: &subscriptions)
        // Handoff is in the menus only while the device has Apple Intelligence.
        Session.shared.$hasIntelligence
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshChrome() }
            .store(in: &subscriptions)
        // The keyboard's first coming in a run of the app (keyboardHasStarted).
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.keyboardStarted() }
            .store(in: &subscriptions)
        // A turn later, once the rows have changed rather than as they are about to.
        model.suggestions.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.placeSuggestions() }
            .store(in: &subscriptions)
        // However typing ends (Return, Escape, another tab), its rows go with
        // it, and the next turn at the field starts with the page's address.
        model.$editingAddress
            .sink { [weak self] editing in
                guard !editing, let self else { return }
                keyboardWait?.cancel()
                keyboardWait = nil
                keyboardWaitOver = false
                model.suggestions.end()
                if model.listsEverything { model.listsEverything = false }
                madeForBar = nil
            }
            .store(in: &subscriptions)
        // A window that turns phone-width (an iPhone, the Duo folding, a narrow
        // iPad window) moves its bars to the bottom, and back.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.refreshChrome()
        }
        // And one that gains or loses the iPhone Duo's vertical bar, or has it on the other side.
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: Self, _: UITraitCollection) in
                self.refreshChrome()
            }
        }
        show(tab: firstTab, inSpace: model.spaceID, userInitiated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        welcomeIfNew()
    }

    /// Only one window welcomes, however many open at a first launch.
    private static var welcoming = false

    /// The first launch's welcome (Welcome.swift), over the first window. It
    /// can't be swiped away by accident; Skip and its last button end it.
    private func welcomeIfNew() {
        guard Session.shared.needsWelcome, !Browser.welcoming, presentedViewController == nil else { return }
        Browser.welcoming = true
        let welcome = UIHostingController(rootView: Welcome(session: Session.shared, spaceID: model.spaceID) { [weak self] in
            Session.shared.finishWelcome()
            self?.dismiss(animated: true) {
                Browser.welcoming = false
                self?.focusPage()
            }
        })
        welcome.modalPresentationStyle = .formSheet
        welcome.preferredContentSize = CGSize(width: 520, height: 680)
        welcome.isModalInPresentation = true
        present(welcome, animated: true)
    }

    /// The window is gone (its scene was closed): its page stays, off
    /// screen now, for the Freezer to decide about.
    func disconnect() {
        connected = false
        detach()
        Session.shared.unregister(self)
        Session.shared.pages.enforce()
    }

    // MARK: Layout

    private func build() {
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        let bottom = stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        safeBottom = bottom
        screenBottom = stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let edge = stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor)
        stackAtEdge = edge
        let stackTop = stack.topAnchor.constraint(equalTo: safe.topAnchor)
        let stackTrailing = stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor)
        self.stackTop = stackTop
        self.stackTrailing = stackTrailing
        NSLayoutConstraint.activate([stackTop, edge, stackTrailing, bottom])

        let session = Session.shared
        // Behind everything: the window's ground, shown with the sidebar.
        let ground = embed(WindowGround(session: session, window: model), inStack: false)
        ground.view.translatesAutoresizingMaskIntoConstraints = false
        ground.view.isHidden = true
        view.sendSubviewToBack(ground.view)
        NSLayoutConstraint.activate([
            ground.view.topAnchor.constraint(equalTo: view.topAnchor),
            ground.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ground.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ground.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        windowGround = ground
        for (shadow, opacity, radius, drop) in [(cardShadow, Float(0.08), CGFloat(14), CGFloat(6)), (cardEdge, 0.16, 1, 0.5)] {
            shadow.isUserInteractionEnabled = false
            shadow.isHidden = true
            shadow.layer.shadowColor = UIColor.black.cgColor
            shadow.layer.shadowOpacity = opacity
            shadow.layer.shadowRadius = radius
            shadow.layer.shadowOffset = CGSize(width: 0, height: drop)
            view.insertSubview(shadow, belowSubview: stack)
        }
        let side = embed(SideTabs(session: session, window: model) { [weak self] in self?.act($0) }, inStack: false)
        side.view.translatesAutoresizingMaskIntoConstraints = false
        side.view.isHidden = true
        let sideWidth = side.view.widthAnchor.constraint(equalToConstant: SideTabs.width)
        self.sideWidth = sideWidth
        NSLayoutConstraint.activate([
            side.view.topAnchor.constraint(equalTo: safe.topAnchor),
            side.view.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            side.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            sideWidth,
        ])
        stackBeside = stack.leadingAnchor.constraint(equalTo: side.view.trailingAnchor)
        sideTabs = side
        let top = embed(TopBar(session: session, window: model) { [weak self] in self?.act($0) })
        top.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        topBar = top

        let address = embed(AddressBar(session: session, window: model) { [weak self] in self?.act($0) })
        address.view.heightAnchor.constraint(equalToConstant: Metrics.bar).isActive = true
        addressBar = address

        let strip = embed(BookmarksStrip(session: session, window: model) { [weak self] in self?.act($0) })
        strip.view.heightAnchor.constraint(equalToConstant: BookmarksStrip.height).isActive = true
        strip.view.isHidden = true
        bookmarksStrip = strip

        let banner = embed(BannerBar(window: model) { [weak self] in self?.act($0) })
        banner.sizingOptions = .intrinsicContentSize
        bannerBar = banner

        stage.clipsToBounds = true
        stage.backgroundColor = Palette.UI.ground
        stage.laidOut = { [weak self] in self?.stageLaidOut() }
        stack.addArrangedSubview(stage)

        // Over the page rather than under it, as Safari's: the page runs on
        // beneath, seen through the bar's blur.
        let phone = embed(PhoneBar(session: session, window: model) { [weak self] in self?.act($0) }, inStack: false)
        phone.view.translatesAutoresizingMaskIntoConstraints = false
        barBackdrop.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(barBackdrop, belowSubview: phone.view)
        let phoneHeight = phone.view.heightAnchor.constraint(equalToConstant: PhoneBar.height)
        let barBottom = phone.view.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        barSafeBottom = barBottom
        barKeyboardBottom = phone.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            phoneHeight, barBottom,
            phone.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            phone.view.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            // A little above the bar, so the page fades into the blur rather than meeting an edge.
            barBackdrop.topAnchor.constraint(equalTo: phone.view.topAnchor, constant: -24),
            barBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            barBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        self.phoneHeight = phoneHeight
        phoneBar = phone
        // A swipe up on the bar shows the tabs, and one sideways goes to the
        // tab beside (slidBar). UIKit's, on the bar's view: SwiftUI's buttons
        // keep a drag that starts on them to themselves.
        let swipe = BarSwipe(target: self, action: #selector(swipedBar(_:)))
        // A second finger doesn't join a swipe already going.
        swipe.maximumNumberOfTouches = 1
        swipe.delegate = self
        phone.view.addGestureRecognizer(swipe)
        barSwipe = swipe
        // A touch on the page while an address is typed puts the typing
        // away, as in Safari; the touch itself stays the page's.
        let away = UITapGestureRecognizer(target: self, action: #selector(touchedPage))
        away.cancelsTouchesInView = false
        away.delaysTouchesBegan = false
        away.delaysTouchesEnded = false
        away.delegate = self
        stage.addGestureRecognizer(away)

        // A click in the pane beside gives it the keys, and the bars.
        let landing = TouchDown(target: nil, action: nil)
        landing.delegate = self
        landing.landed = { [weak self] point in self?.landed(at: point) }
        stage.addGestureRecognizer(landing)

        for frozen in [picture, partnerPicture] {
            frozen.contentMode = .scaleAspectFill
            frozen.clipsToBounds = true
            frozen.isUserInteractionEnabled = false
            frozen.isHidden = true
            frozen.frame = stage.bounds
            stage.addSubview(frozen)
        }

        let blank = UIHostingController(rootView: EmptySpace(session: session, window: model) { [weak self] in self?.act($0) })
        addChild(blank)
        blank.view.frame = stage.bounds
        blank.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blank.view.backgroundColor = .clear
        blank.view.isHidden = true
        stage.addSubview(blank.view)
        blank.didMove(toParent: self)
        empty = blank

        // A new tab's page: the space's bookmarks, until it goes somewhere.
        let start = UIHostingController(rootView: StartPage(session: session, window: model) { [weak self] in self?.act($0) })
        addChild(start)
        start.view.frame = stage.bounds
        start.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        start.view.backgroundColor = Palette.UI.ground
        start.view.isHidden = true
        stage.addSubview(start.view)
        start.didMove(toParent: self)
        self.start = start

        divider.moved = { [weak self] x in self?.dragDivider(to: x) }
        divider.ended = { [weak self] in self?.dropDivider() }
        divider.centered = { [weak self] in
            guard let tab = self?.model.tabID else { return }
            Session.shared.change { $0.setSplitRatio(tab, to: 0.5) }
        }
        stage.addSubview(divider)
        focusEdge.isUserInteractionEnabled = false
        focusEdge.isHidden = true
        stage.addSubview(focusEdge)

        // Over everything else, the bars included: a phone's rows, over its bar.
        let list = embed(SuggestionList(window: model) { [weak self] row in self?.act(.suggestion(row)) },
                         inStack: false)
        list.view.translatesAutoresizingMaskIntoConstraints = false
        list.view.isHidden = true
        // As tall as its rows, as far as the room goes.
        let height = list.view.heightAnchor.constraint(equalToConstant: 0)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            list.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 10),
            list.view.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -10),
            list.view.bottomAnchor.constraint(equalTo: phone.view.topAnchor, constant: -4),
            list.view.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 8),
            height,
        ])
        suggestionHeight = height
        suggestionList = list

        // And an iPad's command bar: in the middle of the page's column (beside
        // the sidebar, when the tabs are there), a little down from the top,
        // as tall as its field and rows as far as the keyboard leaves room.
        let bar = embed(CommandBar(window: model) { [weak self] in self?.act($0) }, inStack: false)
        bar.view.translatesAutoresizingMaskIntoConstraints = false
        bar.sizingOptions = .intrinsicContentSize
        bar.view.isHidden = true
        let barWidth = bar.view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32)
        barWidth.priority = .defaultHigh
        let barTop = bar.view.topAnchor.constraint(equalTo: safe.topAnchor, constant: 96)
        NSLayoutConstraint.activate([
            bar.view.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            bar.view.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
            barWidth,
            barTop,
            bar.view.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
        ])
        commandBarTop = barTop
        commandBar = bar

        refreshChrome()
    }

    /// Shown for the iPhone Duo's strip, the navigation bar puts a band
    /// across the window's top that has nothing in it: its items are in the
    /// strip. The page goes on to the top under it, the band taken back out
    /// of the safe area (Docs/iPhoneDuoDesign.md §3).
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let given = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        let outside = navigationController?.view.safeAreaInsets.top ?? given
        let band = model.strip != nil && navigationController?.isNavigationBarHidden == false ? max(0, given - outside) : 0
        if additionalSafeAreaInsets.top != -band { additionalSafeAreaInsets.top = -band }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The stack places the stage later in this pass, so the stage's frame
        // here is the last pass's: what follows it waits for the stage's own
        // layout, in this same pass (stageLaidOut).
        stage.setNeedsLayout()
        // A sixth of the way down, as Spotlight's sits, and clear of the bars in a short window.
        let down = max(72, (view.bounds.height * 0.16).rounded())
        if let commandBarTop, commandBarTop.constant != down { commandBarTop.constant = down }
    }

    /// The stage has this pass's frame: the card's shadows go behind it and
    /// the panes in it, once a pass.
    private func stageLaidOut() {
        if carded {
            let frame = stage.convert(stage.bounds, to: view)
            for shadow in [cardShadow, cardEdge] where shadow.frame != frame {
                shadow.frame = frame
                shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: Side.card).cgPath
            }
        }
        layoutPanes()
    }

    private func embed<V: View>(_ root: V, inStack: Bool = true) -> UIHostingController<V> {
        let host = UIHostingController(rootView: root)
        // The stack already keeps the bars inside the safe area. Left to
        // SwiftUI, the keyboard's arrival moved what they draw up out of
        // sight, .ignoresSafeArea(.keyboard) or not: both bars went blank
        // whenever a field had the focus (iPadOS 27).
        host.safeAreaRegions = []
        // The window's own colour shows through: the site's (siteColor).
        host.view.backgroundColor = .clear
        addChild(host)
        if inStack { stack.addArrangedSubview(host.view) } else { view.addSubview(host.view) }
        host.didMove(toParent: self)
        return host
    }

    /// Which bars show, from Settings and the page. In the compact layout
    /// the address is in the tab on screen, so the row of tabs shows
    /// whenever an address must: on sign-in pages, while one is typed, when
    /// a page failed, on a new tab, even with the tab bar turned off.
    private func refreshChrome() {
        let session = Session.shared
        let preferences = session.preferences
        // A site's letter, until its icon comes, on the space's colour, in
        // UIKit and SwiftUI alike (SiteIconView).
        let colour = session.workspace.space(model.spaceID)?.color ?? .blue
        if shownColour != colour {
            shownColour = colour
            traitOverrides.spaceColor = colour
        }
        let url = page?.view.url ?? model.tabID.flatMap { session.workspace.tab($0)?.url }
        let signIn = page?.passwordField ?? false
        let failed = page?.failure != nil
        let required = AddressVisibility.shows(mode: .automatic, url: url, passwordField: signIn,
                                               editing: false, failed: failed)
        if model.addressRequired != required { model.addressRequired = required }
        let phone = traitCollection.horizontalSizeClass == .compact
        let strip = phone ? StripEdge(of: traitCollection) : nil
        if model.strip != strip {
            model.strip = strip
            // The bar covers less of the page beside a strip (phoneCovered).
            stage.setNeedsLayout()
        }
        showStrip(strip != nil)
        let makesWindows = Device.makesWindows(on: view.window?.windowScene?.screen.bounds.size ?? view.bounds.size)
        if model.makesWindows != makesWindows { model.makesWindows = makesWindows }
        // Whether a change of width ended an address being typed (below).
        var endedTyping = false
        if model.phone != phone {
            // A window that turns phone-width or back while an address is
            // typed has another field to type it in (the bar at the bottom,
            // the command bar). On an iPad, resized, the typing ends rather
            // than being handed from one to the other with the keys. On a
            // phone (the iPhone Duo opening or closing, a large iPhone
            // turning) it is the same moment for the person typing: what is
            // typed goes over to the other field, the cursor at its end.
            if model.editingAddress {
                if Device.phone {
                    model.carriedAddress = model.suggestions.lastTyped
                    model.addressTurn += 1
                } else {
                    model.editingAddress = false
                    endedTyping = true
                }
            }
            model.phone = phone
        }
        // Typing an address brings no bar out on iPad: it is typed in the
        // command bar, over the page, and the bars keep saying what they said.
        let mustShow = required
        let showsAddress = AddressVisibility.shows(
            mode: preferences.address, url: url, passwordField: signIn, editing: false, failed: failed
        )
        if model.showsAddress != showsAddress { model.showsAddress = showsAddress }
        // The tabs in a sidebar: it has the address too, and while it shows
        // neither bar does. Put away (Show or Hide Tab Bar), the address bar
        // stays, with the way back to it.
        let sidebar = !phone && preferences.tabsPlacement == .sidebar
        let sideShown = sidebar && preferences.tabBar
        if sideTabs?.view.isHidden == sideShown {
            sideTabs?.view.isHidden = !sideShown
            // The one going first, so the two are never on together.
            if sideShown {
                stackAtEdge?.isActive = false
                stackBeside?.isActive = true
            } else {
                stackBeside?.isActive = false
                stackAtEdge?.isActive = true
            }
            card(sideShown)
        }
        topBar?.view.isHidden = phone || sidebar || !(preferences.tabBar || mustShow)
        // Along the top the tab on screen is the address; the bar is for a sidebar put away.
        addressBar?.view.isHidden = phone || !sidebar || sideShown
        // The sidebar has its own Bookmarks section; a phone, its bar alone.
        bookmarksStrip?.view.isHidden = phone || sidebar || !preferences.bookmarksBar
        // On a phone the bar at the bottom is the only way around: always there.
        phoneBar?.view.isHidden = !phone
        // The tabs grow out of the phone's bar; with the bar gone, they go too.
        if !phone { tabSheet?.closeNow() }
        // The one going first, so the two are never on together.
        if phone, safeBottom?.isActive == true {
            safeBottom?.isActive = false
            screenBottom?.isActive = true
        } else if !phone, screenBottom?.isActive == true {
            screenBottom?.isActive = false
            safeBottom?.isActive = true
        }
        // Not before the keyboard is on its way, the first time: see keyboardHasStarted.
        let typing = phone && model.editingAddress && (Self.keyboardHasStarted || keyboardWaitOver)
        if model.barRidesKeyboard != typing { model.barRidesKeyboard = typing }
        // Only the address rides over the keyboard, as in Safari; the page
        // takes the room the tools leave, at the speed the tools go.
        let height = typing ? PhoneBar.typingHeight : PhoneBar.resting(strip: model.strip != nil)
        if let phoneHeight, phoneHeight.constant != height {
            phoneHeight.constant = height
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) { self.view.layoutIfNeeded() }
        }
        if typing, barSafeBottom?.isActive == true {
            barSafeBottom?.isActive = false
            barKeyboardBottom?.isActive = true
        } else if !typing, barKeyboardBottom?.isActive == true {
            barKeyboardBottom?.isActive = false
            barSafeBottom?.isActive = true
        }
        // The desktop view is the phone's, and never on a hands-off page,
        // where nothing may reach the page but the finger.
        if let page, page.desktopView, !Device.phone || page.isHandsOff { leaveDesktopView() }
        let desktop = page?.desktopView ?? false
        if model.desktopView != desktop { model.desktopView = desktop }
        // Any phone's, whichever bars its window has: a large iPhone turned keeps it.
        let canDesktop = Device.phone && page?.view.url != nil && page?.isHandsOff == false
        if model.canDesktopView != canDesktop { model.canDesktopView = canDesktop }
        let canHandoff = preferences.handoff && session.hasIntelligence && page?.view.url != nil && page?.isHandsOff == false
        if model.canHandoff != canHandoff { model.canHandoff = canHandoff }
        if desktop { showDesktopPad() } else if desktopPad != nil { hideDesktopPad() }
        bannerBar?.view.isHidden = model.banner == nil
        start?.view.isHidden = !(page != nil && model.url == nil)
        // Looked up only when the address or the space's bookmarks are other
        // ones: this runs many times as a page loads, and the answer reads
        // every bookmark. (The same array compares at once.)
        let bookmarks = session.workspace.space(model.spaceID)?.bookmarks ?? []
        let bookmarked: Bool
        if let last = starCheck, last.url == url, last.bookmarks == bookmarks {
            bookmarked = last.found
        } else {
            bookmarked = url.flatMap { Bookmarks.find($0, in: bookmarks) } != nil
            starCheck = (url, bookmarks, bookmarked)
        }
        if model.bookmarked != bookmarked { model.bookmarked = bookmarked }
        var blocking: Bool?
        if let host = url?.host, let page, !page.isHandsOff, preferences.blocksContent {
            blocking = preferences.blocksContent(onHost: host)
        }
        if model.blocking != blocking { model.blocking = blocking }
        var ownMenus: Bool?
        if let host = url?.host, let page, !page.isHandsOff { ownMenus = preferences.keepsOwnMenus(onHost: host) }
        if model.ownMenus != ownMenus { model.ownMenus = ownMenus }
        showDiagnostics(preferences.diagnostics)
        applySiteColor()
        placeSuggestions()
        placeCommandBar()
        // The keys go back to the page, as they do however else typing ends
        // (cancelAddress): the field that had them is put away, and with no
        // one holding them a keyboard's keys would go nowhere until the page
        // was tapped. Last, once the bars are where they belong.
        if endedTyping { focusPage() }
    }

    /// A phone's suggestions, over its bar, while there are any and an
    /// address is typed.
    private func placeSuggestions() {
        guard let list = suggestionList else { return }
        let height = SuggestionRows.height(of: model.suggestions)
        let shows = model.phone && model.editingAddress && height > 0
        if list.view.isHidden == shows { list.view.isHidden = !shows }
        if shows { suggestionHeight?.constant = height }
    }

    /// An iPad's command bar, while an address is typed: it comes up out of
    /// the page a little smaller and fades in, and fades out faster than it
    /// came, so the page is back at once.
    private func placeCommandBar() {
        guard let bar = commandBar?.view else { return }
        let shows = model.editingAddress && !model.phone
        guard shows != commandBarShown else { return }
        commandBarShown = shows
        if shows {
            // From where it is when it was still going (⌘T with the bar
            // already open puts it away and brings it back in one turn).
            if bar.isHidden {
                bar.isHidden = false
                bar.alpha = 0
                // Only the fade under Reduce Motion.
                bar.transform = UIAccessibility.isReduceMotionEnabled ? .identity
                    : CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.97, y: 0.97)
            }
            UIView.animate(springDuration: 0.28, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                bar.alpha = 1
                bar.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                bar.alpha = 0
            } completion: { [weak self] _ in
                if self?.commandBarShown == false { bar.isHidden = true }
            }
        }
    }

    /// The bars and the strip under the status bar in the colour along the
    /// top of the page, so page and bars read as one, as in Safari. What
    /// they draw turns light on a dark colour and dark on a light one; a
    /// change of colour eases in rather than flashing.
    ///
    /// The phone bar is at the page's foot, and goes by the colour there
    /// (Page.footColor): its ground fades to it, and what it draws turns
    /// light or dark to read on it. Until the page has been looked at, the
    /// colour of its top is the best guess; over the start page, which is
    /// the app's own, the system's appearance stands.
    private func applySiteColor() {
        let color = model.siteColor
        let style: UIUserInterfaceStyle = color.map { $0.isDark ? .dark : .light } ?? .unspecified
        // The command bar is glass of the space's colour, and the sidebar
        // stands on it, light or dark as the system is: both are left out.
        for bar in [topBar, addressBar, bookmarksStrip, bannerBar] as [UIViewController?]
        where bar?.overrideUserInterfaceStyle != style {
            bar?.overrideUserInterfaceStyle = style
        }
        let foot = model.url == nil ? nil : (page?.footColor ?? color)
        if model.footColor != foot { model.footColor = foot }
        let footStyle: UIUserInterfaceStyle = foot.map { $0.isDark ? .dark : .light } ?? .unspecified
        // And a phone's rows over its bar, as that bar.
        for bar in [phoneBar, suggestionList] as [UIViewController?] where bar?.overrideUserInterfaceStyle != footStyle {
            bar?.overrideUserInterfaceStyle = footStyle
        }
        if barBackdrop.overrideUserInterfaceStyle != footStyle { barBackdrop.overrideUserInterfaceStyle = footStyle }
        barBackdrop.tint = foot?.uiColor
        let ground = carded ? Palette.UI.ground : color?.uiColor ?? Palette.UI.ground
        if view.backgroundColor != ground {
            UIView.animate(withDuration: 0.25) { self.view.backgroundColor = ground }
        }
        // Only when it would change: this runs for every step of a page's
        // loading, and asking is a pass through UIKit whatever the answer.
        let status = preferredStatusBarStyle
        if statusStyle != status {
            statusStyle = status
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    /// The status bar's style as it was last asked for (applySiteColor).
    private var statusStyle: UIStatusBarStyle?

    /// The page as a card on the window's ground, or edge to edge.
    private func card(_ on: Bool) {
        guard on != carded else { return }
        carded = on
        let bezel = on ? Side.bezel : 0
        stackTop?.constant = bezel
        stackTrailing?.constant = -bezel
        safeBottom?.constant = -bezel
        placeSidebar(animated: false)
        stage.layer.cornerRadius = on ? Side.card : 0
        stage.layer.cornerCurve = .continuous
        windowGround?.view.isHidden = !on
        cardShadow.isHidden = !on
        cardEdge.isHidden = !on
        view.setNeedsLayout()
        applySiteColor()
    }

    /// The sidebar's width and the page's start beside it: the sidebar's own
    /// width a bezel from the page; or, on an iPhone Duo folded like a book,
    /// as far as the fold, the page starting past it, so each half of the
    /// display is one of the two (DuoLayout.sidebar). Asked from the root
    /// view's updateConstraints(), where reading the fold makes UIKit ask
    /// again when the fold comes or goes, and as the card comes and goes.
    private func placeSidebar(animated: Bool) {
        guard let sideWidth, let stackBeside else { return }
        var fold: CGRect?
        if #available(iOS 27.1, *), carded {
            fold = view.reservedRegions(kind: .division).first?.frame
        }
        let rightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let start = rightToLeft ? view.bounds.width - view.safeAreaInsets.right : view.safeAreaInsets.left
        let sidebar = DuoLayout.sidebar(start: start, fold: fold, rightToLeft: rightToLeft, standard: SideTabs.width,
                                        minimum: SideTabs.width, gap: carded ? Side.bezel : 0)
        guard sideWidth.constant != sidebar.width || stackBeside.constant != sidebar.gap else { return }
        guard animated, !UIAccessibility.isReduceMotionEnabled, view.window != nil else {
            sideWidth.constant = sidebar.width
            stackBeside.constant = sidebar.gap
            return
        }
        // Not inside the constraints pass that read the fold: the next turn,
        // growing into the half (or back) as the device folds.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            sideWidth.constant = sidebar.width
            stackBeside.constant = sidebar.gap
            UIView.animate(springDuration: 0.35, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.view.layoutIfNeeded()
            }
        }
    }

    // MARK: The keyboard's first coming

    /// Whether the keyboard has come up in this run of the app. The first
    /// time it takes the system a moment to start it, a second and more in
    /// the simulator, and nothing the app draws shows until it is there.
    /// A phone's bar that had already shrunk to ride over it sat at the foot
    /// of the screen for that moment, its tools cut off, looking broken. So
    /// the first time the bar keeps its place until the keyboard says it is
    /// coming, and goes up with it; after that it is quick, and the bar
    /// makes room at the tap as before.
    private static var keyboardHasStarted = false

    /// Every window hears of the keyboard, in no order: the one being typed
    /// in makes room whichever heard first.
    private func keyboardStarted() {
        Self.keyboardHasStarted = true
        if model.phone, model.editingAddress, !model.barRidesKeyboard { refreshChrome() }
    }

    /// With no keyboard to come (a keyboard with keys is attached), the bar
    /// makes room a moment after the tap all the same: for this turn at the
    /// address only, since no keyboard has started. One wait at a time, and
    /// none left over once the typing ends.
    private func awaitKeyboard() {
        guard !Self.keyboardHasStarted, keyboardWait == nil else { return }
        keyboardWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            keyboardWait = nil
            keyboardWaitOver = true
            if model.phone, model.editingAddress, !model.barRidesKeyboard { refreshChrome() }
        }
    }

    /// The first keyboard's wait for this turn at the address (awaitKeyboard).
    private var keyboardWait: Task<Void, Never>?
    private var keyboardWaitOver = false

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // Over the space's colour, with the sidebar, as the system's look has it.
        guard !carded, let color = model.siteColor else { return .default }
        return color.isDark ? .lightContent : .darkContent
    }

    private func showDiagnostics(_ on: Bool) {
        if !on {
            diagnostics?.willMove(toParent: nil)
            diagnostics?.view.removeFromSuperview()
            diagnostics?.removeFromParent()
            diagnostics = nil
            if let hingeWatch { view.removeInteraction(hingeWatch) }
            hingeWatch = nil
            return
        }
        guard diagnostics == nil else { return }
        // The iPhone Duo's hinge, for the panel to show.
        if #available(iOS 27.1, *) {
            let watch = UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    Diagnostics.hinge = "none"
                    return
                }
                let status = switch hinge.status {
                case .closed: "closed"
                case .partiallyOpen: "partly open"
                case .fullyOpen: "open"
                default: "unknown"
                }
                Diagnostics.hinge = "\(status) \(Int((hinge.angle * 180 / .pi).rounded()))°"
            }
            view.addInteraction(watch)
            hingeWatch = watch
        }
        let hud = UIHostingController(rootView: DiagnosticsView(page: { [weak self] in self?.page },
                                                                window: { [weak self] in self?.view }))
        hud.view.backgroundColor = .clear
        hud.view.isUserInteractionEnabled = false
        hud.sizingOptions = .intrinsicContentSize
        addChild(hud)
        hud.view.translatesAutoresizingMaskIntoConstraints = false
        // Under a phone's rows and an iPad's command bar, which are what is being used.
        if let rows = suggestionList?.view { view.insertSubview(hud.view, belowSubview: rows) } else { view.addSubview(hud.view) }
        // On a phone, above the bar at the bottom rather than under it.
        let bottom = model.phone ? phoneBar.map { hud.view.bottomAnchor.constraint(equalTo: $0.view.topAnchor, constant: -12) } : nil
        NSLayoutConstraint.activate([
            hud.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            // Clear of a side the system keeps, as the iPhone Duo's status bar strip.
            hud.view.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            bottom ?? hud.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        hud.didMove(toParent: self)
        diagnostics = hud
    }

    // MARK: Showing a tab

    /// Shows a tab in this window. One another window shows is brought
    /// forward there instead when you asked for it; a window coming back
    /// takes another tab of its space, or none.
    func show(tab id: UUID?, inSpace space: UUID, userInitiated: Bool = true) {
        let session = Session.shared
        guard let id, let record = session.workspace.tab(id), let owner = session.workspace.spaceID(of: id) else {
            showEmpty(space: session.workspace.space(space) == nil ? session.workspace.firstSpace.id : space)
            return
        }
        if let other = session.browser(showing: id), other !== self {
            if userInitiated {
                session.bringForward(other)
            } else if let free = session.workspace.space(owner)?.tabs.first(where: { session.browser(showing: $0.id) == nil }) {
                show(tab: free.id, inSpace: owner, userInitiated: false)
            } else {
                showEmpty(space: owner)
            }
            return
        }
        // Already here, and still live: a tab moved to another space has a
        // new page to load in that space's store.
        if model.tabID == id, let page, session.pages.live[id] === page {
            focusPage()
            return
        }
        let pairedWith = session.workspace.split(containing: id)?.partner(of: id)
        // The pane beside, still split with the tab on screen: it takes the keys.
        if let partner, partner.tab == id, session.pages.live[id] === partner, let page, pairedWith == page.tab {
            swapPanes()
            return
        }
        // The tab on screen split with the one asked for stays up, as the other pane.
        if let page, pairedWith == page.tab, session.pages.live[page.tab] === page {
            detachPartner()
            self.page = nil
            partner = page
            partnerPicture.image = picture.image
            partnerPicture.alpha = picture.alpha
            partnerPicture.isHidden = picture.isHidden
            picture.isHidden = true
            picture.image = nil
        } else {
            detach()
        }
        let made = session.pages.page(for: record, in: owner)
        attach(made.page, thawed: made.thawed)
        // Going to another tab ends typing an address, as in Safari.
        model.editingAddress = false
        model.spaceID = owner
        model.tabID = id
        session.change { $0.select(id) }
        syncSplit()
        pageDidChange(made.page)
        focusPage()
        session.pages.enforce()
    }

    /// The other pane takes the keys: the bars show its page from now on.
    private func swapPanes() {
        guard let partner, let page else { return }
        self.page = partner
        self.partner = page
        let frozen = (picture.image, picture.alpha, picture.isHidden)
        picture.image = partnerPicture.image
        picture.alpha = partnerPicture.alpha
        picture.isHidden = partnerPicture.isHidden
        (partnerPicture.image, partnerPicture.alpha, partnerPicture.isHidden) = frozen
        model.editingAddress = false
        model.tabID = partner.tab
        Session.shared.change { $0.select(partner.tab) }
        layoutPanes()
        pageDidChange(partner)
        focusPage()
    }

    /// A touch or a click landed on the stage: in the pane beside, that pane
    /// gets the keys. The touch itself goes on to the page.
    private func landed(at point: CGPoint) {
        guard let partner, !partner.view.isHidden, partner.view.frame.contains(point) else { return }
        show(tab: partner.tab, inSpace: model.spaceID)
    }

    /// The tab split with the one on screen, up in its pane beside it; or
    /// taken down, when their split has ended or another window shows that
    /// tab.
    func syncSplit() {
        let session = Session.shared
        let workspace = session.workspace
        guard connected, let tab = model.tabID, page != nil, let other = workspace.split(containing: tab)?.partner(of: tab),
              let record = workspace.tab(other), let space = workspace.spaceID(of: other),
              !session.allBrowsers.contains(where: { $0 !== self && $0.isConnected && $0.shows(other) })
        else {
            if partner != nil {
                detachPartner()
                session.pages.enforce()
            }
            layoutPanes()
            return
        }
        if partner?.tab != other || session.pages.live[other] !== partner {
            detachPartner()
            let made = session.pages.page(for: record, in: space)
            made.page.host = self
            stage.insertSubview(made.page.view, at: 0)
            partner = made.page
            if made.thawed, let image = session.pages.picture(for: other) {
                partnerPicture.image = image
                partnerPicture.alpha = 1
                partnerPicture.isHidden = false
            }
            session.pages.enforce()
        }
        layoutPanes()
    }

    private func detachPartner() {
        guard let partner else { return }
        if partner.view.superview === stage { partner.view.removeFromSuperview() }
        if partner.host === self { partner.host = nil }
        self.partner = nil
        partnerPicture.isHidden = true
        partnerPicture.image = nil
    }

    /// The narrowest a window shows a split in: two pages each wide enough
    /// to read. Narrower, only the pane with the keys shows, and a click on
    /// the other half of the split's tab goes over to the other.
    private static let splitWidth: CGFloat = 2 * 360 + SplitDivider.width

    /// The tab on screen across the stage; or a split's two side by side,
    /// the divider between them and a line in the space's colour along the
    /// top of the one with the keys.
    private func layoutPanes() {
        let bounds = stage.bounds
        var main = bounds
        let split = model.tabID.flatMap { Session.shared.workspace.split(containing: $0) }
        if let page, let partner, let split, split.contains(partner.tab), bounds.width >= Self.splitWidth {
            let gap = SplitDivider.width
            let ratio = CGFloat(dragRatio ?? split.ratio)
            let leftWidth = ((bounds.width - gap) * ratio).rounded()
            let left = CGRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
            let right = CGRect(x: leftWidth + gap, y: 0, width: bounds.width - leftWidth - gap, height: bounds.height)
            let onLeft = split.left == page.tab
            main = onLeft ? left : right
            partner.view.frame = onLeft ? right : left
            partner.view.isHidden = false
            partnerPicture.frame = partner.view.frame
            partnerPicture.isHidden = partnerPicture.image == nil
            divider.frame = CGRect(x: leftWidth, y: 0, width: gap, height: bounds.height)
            divider.isHidden = false
            // Each pane a card on the band: its corners along the band rounded.
            let leftCorners: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            let rightCorners: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            let mainCorners = onLeft ? leftCorners : rightCorners
            let partnerCorners = onLeft ? rightCorners : leftCorners
            for (view, corners) in [(page.view, mainCorners), (picture, mainCorners),
                                    (partner.view, partnerCorners), (partnerPicture, partnerCorners)] as [(UIView, CACornerMask)] {
                round(view, corners)
            }
            // The line along the top of the pane with the keys stops short of its rounded corner.
            let inset = SplitDivider.corner
            focusEdge.frame = CGRect(x: main.minX + (onLeft ? 0 : inset), y: 0, width: main.width - inset, height: 2)
            focusEdge.backgroundColor = Session.shared.workspace.space(model.spaceID)?.color.uiColor ?? .tintColor
            focusEdge.isHidden = false
        } else {
            partner?.view.isHidden = true
            partnerPicture.isHidden = true
            divider.isHidden = true
            focusEdge.isHidden = true
            for view in [page?.view, picture, partner?.view, partnerPicture].compactMap({ $0 }) { round(view, []) }
        }
        // Under the phone bar and the home indicator: the page goes on
        // there, told it is covered so its end scrolls clear of the bar and
        // its own bottom bars sit above it. The desktop view's page too, the
        // cursor and the view kept above the bar; past the desktop's own
        // edge, the page's own colour rather than the window's, so the bar
        // sits on the page.
        let covered = phoneCovered
        if let page, let pad = desktopPad, pad.page === page {
            laidClear = false
            pad.layout(in: main, covered: covered)
            page.obscure(bottom: 0)
            page.footBand = covered
            stage.backgroundColor = page.view.underPageBackgroundColor
        } else {
            page?.view.transform = .identity
            // A page that only fills the window stands clear of the bar: laid out in the window
            // less the bar, with its own colour under the bar in place of its foot (FootRoom).
            page?.room(window: main.height, covered: covered)
            let clear = covered > 0 && page?.standsClear == true
            laidClear = clear
            var room = main
            if clear { room.size.height -= covered }
            page?.view.frame = room
            page?.obscure(bottom: clear ? 0 : covered)
            page?.footBand = covered
            // A split's band shows behind its panes' rounded corners too.
            let ground = divider.isHidden ? Palette.UI.ground : Palette.UI.splitBand
            stage.backgroundColor = clear ? (page?.footColor?.uiColor ?? page?.view.underPageBackgroundColor ?? ground) : ground
        }
        picture.frame = main
        // The start page runs on under the bar too, its own ground behind
        // the bar's blur rather than whatever the window has there; its
        // tiles keep clear of the bar, as a page's end does.
        start?.view.frame = main
        let bar = covered > 0 ? PhoneBar.resting(strip: model.strip != nil) : 0
        if start?.additionalSafeAreaInsets.bottom != bar { start?.additionalSafeAreaInsets.bottom = bar }
        barBackdrop.isHidden = !model.phone
    }

    /// Whether the page on screen was last laid out clear of the phone bar (Page.standsClear).
    private var laidClear = false

    /// How much of the stage's bottom the phone bar covers, with the home
    /// indicator under it: always the bar's resting height, so typing an
    /// address doesn't move the page.
    private var phoneCovered: CGFloat {
        guard model.phone, phoneBar?.view.isHidden == false else { return 0 }
        return view.safeAreaInsets.bottom + PhoneBar.resting(strip: model.strip != nil)
    }

    /// The strip's tools stay in reach where the phone bar's go (an address
    /// typed, the tabs out), so what one does first puts those away: the
    /// typing ends, as a touch on the page ends it; the tabs go, and Tabs
    /// again only puts them away, as the overview's own buttons do.
    private func fromStrip(_ action: BarAction) {
        if tabSheet != nil {
            if case .showTabs = action { closeTabs(then: nil) } else { closeTabs(then: action) }
            return
        }
        if model.editingAddress { act(.cancelAddress) }
        act(action)
    }

    /// The system's bars, which stand in the iPhone Duo's strip, shown only
    /// while the window has one (StripItems); the phone bar is one row then.
    private func showStrip(_ shown: Bool) {
        guard let navigation = navigationController else { return }
        if shown, stripItems == nil {
            stripItems = StripItems(in: self, session: .shared, window: model) { [weak self] in self?.fromStrip($0) }
        }
        // The page beside, slid in from the side, comes from the strip's edge, not from under it.
        if stack.clipsToBounds != shown { stack.clipsToBounds = shown }
        guard navigation.isNavigationBarHidden == shown else { return }
        navigation.setNavigationBarHidden(!shown, animated: false)
        navigation.setToolbarHidden(!shown, animated: false)
        // The navigation bar's band at the top, taken back for the page (viewSafeAreaInsetsDidChange).
        if !shown, additionalSafeAreaInsets.top != 0 { additionalSafeAreaInsets.top = 0 }
    }


    /// A pane's corners along a split's band, rounded; none outside a split.
    private func round(_ view: UIView, _ corners: CACornerMask) {
        let radius = corners.isEmpty ? 0 : SplitDivider.corner
        guard view.layer.cornerRadius != radius || view.layer.maskedCorners != corners else { return }
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = corners.isEmpty ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] : corners
        // A frozen page's picture always clips, to crop it; a page only for its corners.
        view.layer.masksToBounds = !corners.isEmpty || view is UIImageView
    }

    private func dragDivider(to x: CGFloat) {
        let width = stage.bounds.width - SplitDivider.width
        guard width > 0 else { return }
        let ratio = Double((x - SplitDivider.width / 2) / width)
        dragRatio = min(max(ratio, Split.ratios.lowerBound), Split.ratios.upperBound)
        layoutPanes()
    }

    private func dropDivider() {
        guard let ratio = dragRatio, let tab = model.tabID else { return }
        Session.shared.change { $0.setSplitRatio(tab, to: ratio) }
        dragRatio = nil
        layoutPanes()
    }

    func showSpace(_ space: UUID) {
        let session = Session.shared
        guard let target = session.workspace.space(space) else { return }
        // A tab this window has beside the one on screen is free for it.
        let free = { (tab: UUID) -> Bool in
            let shower = session.browser(showing: tab)
            return shower == nil || shower === self
        }
        let choice = [target.selected].compactMap { $0 }.first(where: free) ?? target.tabs.first { free($0.id) }?.id
        if let choice {
            show(tab: choice, inSpace: space, userInitiated: false)
        } else {
            showEmpty(space: space)
        }
    }

    private func showEmpty(space: UUID) {
        detach()
        model.spaceID = space
        model.tabID = nil
        model.url = nil
        model.title = ""
        model.banner = nil
        model.loading = false
        model.siteColor = nil
        empty?.view.isHidden = false
        refreshChrome()
        updateSceneTitle()
    }

    private func attach(_ page: Page, thawed: Bool) {
        // Another tab on screen: the next ⌘-click starts again right after
        // its own tab, as in Safari and Chrome.
        if openedBehind?.from != page.tab { openedBehind = nil }
        page.host = self
        page.view.frame = stage.bounds
        page.view.autoresizingMask = []
        page.view.isHidden = false
        stage.insertSubview(page.view, at: 0)
        empty?.view.isHidden = true
        self.page = page
        if thawed, let image = Session.shared.pages.picture(for: page.tab) {
            picture.image = image
            picture.alpha = 1
            picture.isHidden = false
        }
    }

    private func detach() {
        detachPartner()
        guard let page else { return }
        // While it still shows: the tab overview's picture of it.
        if model.phone { Session.shared.pages.keepPreview(of: page) }
        if page.view.superview === stage { page.view.removeFromSuperview() }
        if page.host === self { page.host = nil }
        self.page = nil
        picture.isHidden = true
        picture.image = nil
    }

    /// The picture of a frozen tab, taken away once its page has loaded.
    private func fadePicture() {
        guard !picture.isHidden, let page, !page.view.isLoading else { return }
        // Its page is back: the picture, a whole screen's, has done its work.
        Session.shared.pages.forgetPicture(of: page.tab)
        UIView.animate(withDuration: 0.2, animations: { self.picture.alpha = 0 }) { _ in
            self.picture.isHidden = true
            self.picture.image = nil
        }
    }

    private func workspaceChanged() {
        defer { refreshChrome() }
        let workspace = Session.shared.workspace
        if workspace.space(model.spaceID) == nil {
            showSpace(workspace.firstSpace.id)
            return
        }
        if let tab = model.tabID {
            if workspace.tab(tab) == nil {
                showSpace(model.spaceID)
                return
            }
            if let owner = workspace.spaceID(of: tab), owner != model.spaceID { model.spaceID = owner }
        }
        syncSplit()
        updateSceneTitle()
    }

    private func updateSceneTitle() {
        let space = Session.shared.workspace.space(model.spaceID)?.name ?? ""
        let title = model.title.isEmpty ? space : "\(model.title) · \(space)"
        // Asked after every change to the page; the system hears only a new one.
        if let scene = view.window?.windowScene, scene.title != title { scene.title = title }
    }

    /// The keys back to the page: whenever the window becomes active, and
    /// after anything that took them (the address bar, a sheet).
    func focusPage() {
        guard let page, presentedViewController == nil, tabSheet == nil, !model.editingAddress else { return }
        _ = page.view.becomeFirstResponder()
    }

    // MARK: PageHost

    func pageDidChange(_ page: Page) {
        if page === partner, !partnerPicture.isHidden, !page.view.isLoading {
            Session.shared.pages.forgetPicture(of: page.tab)
            UIView.animate(withDuration: 0.2, animations: { self.partnerPicture.alpha = 0 }) { _ in
                self.partnerPicture.isHidden = true
                self.partnerPicture.image = nil
            }
        }
        guard page === self.page else { return }
        let view = page.view
        // The page's colour behind the desktop view, as it loads and changes.
        if desktopPad?.page === page { stage.backgroundColor = view.underPageBackgroundColor }
        // A page that has come to stand clear of the phone bar, or to run under it again, is laid out anew.
        let clear = page.standsClear && desktopPad?.page !== page && phoneCovered > 0
        if clear != laidClear { layoutPanes() }
        if laidClear { stage.backgroundColor = page.footColor?.uiColor ?? view.underPageBackgroundColor }
        model.set(\.url, to: view.url ?? Session.shared.workspace.tab(page.tab)?.url)
        model.set(\.title, to: view.title ?? "")
        model.set(\.loading, to: view.isLoading)
        if model.load.fraction != view.estimatedProgress { model.load.fraction = view.estimatedProgress }
        model.set(\.canGoBack, to: view.canGoBack)
        model.set(\.canGoForward, to: view.canGoForward)
        model.set(\.secure, to: view.hasOnlySecureContent)
        model.set(\.signIn, to: page.isSignIn)
        model.set(\.siteColor, to: page.siteColor)
        model.set(\.mobileSite, to: page.mode == .mobile)
        if page.googleRefused {
            model.set(\.banner, to: .googleRefused)
        } else if page.exhausted {
            model.set(\.banner, to: .exhausted)
        } else {
            model.set(\.banner, to: page.failure.map(Banner.failed))
        }
        refreshChrome()
        updateSceneTitle()
        fadePicture()
    }

    func pageDidAdvance(_ page: Page) {
        guard page === self.page else { return }
        let fraction = page.view.estimatedProgress
        if model.load.fraction != fraction { model.load.fraction = fraction }
    }

    func isShowing(_ page: Page) -> Bool {
        connected && (page === self.page || page === partner)
    }

    func page(_ page: Page, open configuration: WKWebViewConfiguration, for action: WKNavigationAction,
              features: WKWindowFeatures) -> WKWebView? {
        // A window with a size asked for is a pop-up: a sign-in, a share
        // dialog. It opens over this window and closes by itself when done.
        if features.width != nil || features.height != nil {
            let popup = Popup(opener: page, configuration: configuration)
            popup.closed = { [weak self] in self?.focusPage() }
            present(popup, animated: true)
            return popup.page.view
        }
        // Anything else is a tab, right after the one it came from; behind
        // this one when a ⌘-click asked for it (a page that answers ⌘-click
        // with window.open), live there with its tie to this page.
        let session = Session.shared
        let behind = page.newTabChoice(for: action) == .behind
        guard let id = session.change({ $0.openTab(action.request.url, in: page.space,
                                                   after: behind ? behindAfter(page) : page.tab) }) else {
            return nil
        }
        let child = session.pages.adopt(tab: id, space: page.space, configuration: configuration)
        if behind {
            openedBehind = (page.tab, id)
            session.pages.enforce()
            return child.view
        }
        openedBehind = nil
        detach()
        attach(child, thawed: false)
        model.tabID = id
        model.spaceID = page.space
        syncSplit()
        pageDidChange(child)
        focusPage()
        session.pages.enforce()
        return child.view
    }

    func page(_ page: Page, openInNewTab url: URL, inFront: Bool) -> Bool {
        let session = Session.shared
        let after = inFront ? page.tab : behindAfter(page)
        guard let id = session.change({ workspace -> UUID? in
            let id = workspace.openTab(url, in: page.space, after: after)
            // Opened behind: the tab on screen stays the one the space opens on next time.
            if !inFront, id != nil { workspace.select(page.tab) }
            return id
        }) else {
            return false
        }
        if inFront {
            openedBehind = nil
            show(tab: id, inSpace: page.space)
        } else {
            // It loads when it is first shown, as every tab not on screen does.
            openedBehind = (page.tab, id)
        }
        return true
    }

    /// Where a tab opened behind goes: after the last one opened behind
    /// from the same tab, so several ⌘-clicks keep their order, as in Safari.
    private func behindAfter(_ page: Page) -> UUID {
        if let last = openedBehind, last.from == page.tab, Session.shared.workspace.tab(last.opened) != nil {
            return last.opened
        }
        return page.tab
    }

    func pageDidClose(_ page: Page) {
        guard page === self.page || page === partner else { return }
        Session.shared.closeTab(page.tab)
    }

    var presenter: UIViewController? {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    // MARK: Commands

    override var keyCommands: [UIKeyCommand]? {
        if tabSheet != nil {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeTabsKey))
            escape.wantsPriorityOverSystemBehavior = true
            return (super.keyCommands ?? []) + [escape]
        }
        guard model.editingAddress else { return (super.keyCommands ?? []) + phoneKeys }
        var keys = [(UIKeyCommand.inputEscape, #selector(cancelAddress))]
        // ↑ and ↓ through the suggestions, ahead of the field's own start and end of line.
        if !model.suggestions.rows.isEmpty {
            keys += [(UIKeyCommand.inputUpArrow, #selector(suggestionUp)), (UIKeyCommand.inputDownArrow, #selector(suggestionDown))]
        }
        return (super.keyCommands ?? []) + keys.map { input, action in
            let key = UIKeyCommand(input: input, modifierFlags: [], action: action)
            key.wantsPriorityOverSystemBehavior = true
            return key
        }
    }

    /// The browser's keys on a phone with a keyboard attached, where UIKit
    /// hasn't built the main menu that carries them (Menus.built): every
    /// command this window has, and Tab 1 to 9.
    private var phoneKeys: [UIKeyCommand] {
        guard Device.phone, !Menus.built, GCKeyboard.coalesced != nil else { return [] }
        let commands = ShortcutGroup.allCases.flatMap(\.commands).filter { Device.offers($0, in: model) }
        return commands.compactMap { Menus.keyCommand($0) } + Menus.tabNumbers()
    }

    /// The main menu has every command a window of this device can have:
    /// those this window can't (an iPhone Duo closed has no tab bar) are
    /// hidden while it has the keys, and do nothing.
    override func validate(_ command: UICommand) {
        super.validate(command)
        guard command.action == #selector(browserCommand(_:)), let raw = command.propertyList as? String,
              let browserCommand = Command(rawValue: raw), !Device.offers(browserCommand, in: model)
        else { return }
        command.attributes.insert(.hidden)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(browserCommand(_:)), let command = sender as? UICommand,
           let raw = command.propertyList as? String, let browserCommand = Command(rawValue: raw) {
            return Device.offers(browserCommand, in: model)
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc func browserCommand(_ sender: UICommand) {
        guard let raw = sender.propertyList as? String, let command = Command(rawValue: raw) else { return }
        perform(command)
    }

    @objc func browserTab(_ sender: UICommand) {
        guard let number = sender.propertyList as? Int else { return }
        selectTab(number: number)
    }

    @objc private func cancelAddress() {
        act(.cancelAddress)
    }

    @objc private func suggestionUp() {
        model.suggestions.move(-1)
    }

    @objc private func suggestionDown() {
        model.suggestions.move(1)
    }

    /// Escape: the tabs go at once, as anything the keys do goes, unanimated.
    @objc private func closeTabsKey() {
        afterTabs = nil
        tabSheet?.closeNow()
    }

    @objc private func touchedPage() {
        if model.editingAddress { act(.cancelAddress) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let swipe = barSwipe, gestureRecognizer === swipe else { return true }
        // Never while an address is typed, where drags are the text field's.
        guard !model.editingAddress else { return false }
        let velocity = swipe.velocity(in: swipe.view)
        // More up than across: the tabs, drawn up out of the bar. Not while
        // a slide settles, with the page still between two tabs.
        if abs(velocity.x) <= abs(velocity.y) {
            guard velocity.y < 0, barGesture == .idle else { return false }
            barGesture = .tabs
            return true
        }
        // More across than up: the tab beside, where the space has one. Not
        // in the desktop view, whose page is laid out by its own trackpad,
        // nor while the tabs are out or sinking back into the bar. A slide
        // still settling is caught where it is, and the finger goes on with it.
        guard model.phone, desktopPad == nil, tabSheet == nil, presentedViewController == nil,
              barGesture == .idle || barGesture == .settling
        else { return false }
        let caught = barGesture == .settling ? catchSlide() : 0
        guard caught != 0 || tabBeside(1) != nil || tabBeside(-1) != nil else { return false }
        slideBase = caught
        slideTicked = false
        slideTick.prepare()
        barGesture = .sliding
        return true
    }

    /// A swipe up on the bar draws the tabs up out of it, under the finger
    /// (TabSheet). Measured against the window's view: the bar moves with
    /// the finger, so against the bar a drag would seem to go nowhere.
    @objc private func swipedBar(_ swipe: UIPanGestureRecognizer) {
        if barGesture == .sliding {
            slidBar(swipe)
            return
        }
        switch swipe.state {
        case .began:
            guard presentedViewController == nil, let sheet = makeTabSheet() else { return }
            sheet.beginDrag()
        case .changed:
            tabSheet?.drag(up: -swipe.translation(in: view).y)
        case .ended:
            tabSheet?.release(up: -swipe.velocity(in: view).y)
            barGesture = .idle
        case .cancelled, .failed:
            tabSheet?.release(up: 0)
            barGesture = .idle
        default:
            break
        }
    }

    // MARK: A sideways swipe on the phone bar

    /// A sideways drag on the bar goes to the tab beside, as in Safari: the
    /// page and the address go with the finger, the tab beside coming in
    /// next to them, and letting go carries on at the finger's speed to
    /// whichever of the two it was heading for. At the first and the last
    /// tab the drag gives less and less, and springs back.
    private func slidBar(_ swipe: UIPanGestureRecognizer) {
        switch swipe.state {
        case .changed:
            slide(to: slideBase + swipe.translation(in: view).x)
        case .ended:
            endSlide(velocity: swipe.velocity(in: view).x)
        case .cancelled, .failed:
            endSlide(velocity: 0, cancelled: true)
        default:
            break
        }
    }

    /// The tab next in the row on that side (1 the right, -1 the left), if
    /// this window can show it: no going round, as there is none in the row.
    private func tabBeside(_ side: CGFloat) -> TabRecord? {
        let session = Session.shared
        guard let current = model.tabID, let tab = session.workspace.tabBeside(current, by: side > 0 ? 1 : -1),
              session.browser(showing: tab.id) == nil
        else { return nil }
        return tab
    }

    private func slide(to distance: CGFloat) {
        guard distance != 0 else { return }
        // A drag to the left brings in the tab on the right.
        let side: CGFloat = distance < 0 ? 1 : -1
        if side != slideSide {
            slideSide = side
            slideCard?.removeFromSuperview()
            slideCard = nil
            if let tab = tabBeside(side) {
                let held = Session.shared.pages.slidePicture(for: tab.id)
                let card = SlideCard(tab: tab, picture: held)
                // From the stage's centre: its frame has the drag's offset in it
                // while it is moved, and the card is moved by the same again.
                card.bounds = stage.bounds
                card.center = CGPoint(x: stage.center.x + side * (stage.bounds.width + Self.slideGap), y: stage.center.y)
                stack.insertSubview(card, aboveSubview: stage)
                slideCard = card
                // A frozen tab's picture may be on disk only: it joins the card when it has been read.
                if held == nil, !Session.shared.pages.isLive(tab.id) {
                    Session.shared.pages.readPicture(for: tab.id) { [weak card] picture in
                        if let picture { card?.show(picture) }
                    }
                }
                let titled = !AddressVisibility.shows(mode: Session.shared.preferences.address, url: tab.url,
                                                      passwordField: false, editing: false, failed: false)
                model.slide.coming = SlideNeighbour(tab: tab, side: side, titled: titled)
            } else {
                model.slide.coming = nil
            }
        }
        // With nothing on that side the page gives less the further it is pulled.
        let width = stage.bounds.width
        let moved = slideCard != nil ? distance : Throw.rubberband(distance, range: width)
        place(slide: moved)
        model.slide.offset = moved
        // Felt as the drag crosses half the way: letting go slowly past it goes to the tab beside.
        let past = slideCard != nil && abs(moved) > (width + Self.slideGap) / 2
        if past != slideTicked {
            slideTicked = past
            slideTick.impactOccurred(intensity: past ? 1 : 0.6)
        }
    }

    private func place(slide distance: CGFloat) {
        let moved = CGAffineTransform(translationX: distance, y: 0)
        stage.transform = moved
        slideCard?.transform = moved
    }

    private func endSlide(velocity: CGFloat, cancelled: Bool = false) {
        let from = stage.transform.tx
        let width = stage.bounds.width + Self.slideGap
        // Where the drag would come to rest by itself, as a scroll's flick does.
        let coming = cancelled ? nil : slideCard.map(\.tab)
        let goes = coming != nil && Throw.slideGoes(offset: from, velocity: velocity, side: slideSide, width: width)
        let target = goes ? -slideSide * width : 0
        guard from != target else {
            finishSlide(to: nil)
            return
        }
        barGesture = .settling
        let count = settling.count + 1
        settling = (target, goes ? coming : nil, count)
        // The spring starts at the finger's speed, so letting go has no seam;
        // the address row's too, so it keeps up with the page.
        let start = min(max(velocity / (target - from), 0), 30)
        UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: start,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.place(slide: target)
        } completion: { _ in
            // Not when a finger caught it on the way (catchSlide), which ended it itself.
            guard self.settling.count == count, self.barGesture == .settling else { return }
            self.finishSlide(to: goes ? coming : nil)
        }
        withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: start)) { model.slide.offset = target }
    }

    /// A sideways swipe taking a slide that is still settling: it ends where
    /// it was going at once (on the tab beside, if it was going there), and
    /// the page is put back where it showed, for the new drag to go on from.
    /// Returns that place, measured from the page now on screen.
    private func catchSlide() -> CGFloat {
        let shown = stage.layer.presentation()?.affineTransform().tx ?? stage.transform.tx
        let (target, goes, _) = settling
        settling.count += 1
        let card = slideCard
        stage.layer.removeAllAnimations()
        card?.layer.removeAllAnimations()
        finishSlide(to: goes)
        // Its picture would fade where the page was at rest, not where it is now.
        card?.removeFromSuperview()
        // finishSlide put the stage at rest: where it showed, relative to it.
        let base = shown - target
        place(slide: base)
        model.slide.offset = base
        return base
    }

    private func finishSlide(to tab: TabRecord?) {
        let card = slideCard
        // Only if it is still the tab beside the one on screen: not when the
        // tab was closed, or another gone to, while the slide settled.
        let tab = tab.flatMap { tabBeside(slideSide)?.id == $0.id ? $0 : nil }
        slideCard = nil
        slideSide = 0
        barGesture = .idle
        if let tab { show(tab: tab.id, inSpace: model.spaceID) }
        // The stage is back where it was, now with the tab that came in, and
        // the bar with it, in one step: nothing to see move.
        stage.transform = .identity
        card?.transform = .identity
        card?.frame = stage.frame
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.slide.offset = 0
            model.slide.coming = nil
        }
        guard let card else { return }
        guard tab != nil else {
            card.removeFromSuperview()
            return
        }
        // Its picture stays a moment over the page it stood for, then fades,
        // so the page's first frame never shows as a flash.
        UIView.animate(withDuration: 0.18, delay: 0.06, options: [.allowUserInteraction]) {
            card.alpha = 0
        } completion: { _ in
            card.removeFromSuperview()
        }
    }

    func perform(_ command: Command) {
        let session = Session.shared
        switch command {
        case .everything:
            model.listsEverything = true
            act(.editAddress)
        case .address:
            // Back to the page's address, if everything was listed.
            if model.listsEverything { model.listsEverything = false }
            act(.editAddress)
        case .newTab: newTab()
        case .closeTab:
            if let tab = model.tabID { session.closeTab(tab) }
        case .reopenTab:
            if let tab = session.change({ $0.reopen() }) { show(tab: tab, inSpace: model.spaceID) }
        case .reload: page?.reload()
        case .stop: page?.view.stopLoading()
        case .back: page?.view.goBack()
        case .forward: page?.view.goForward()
        case .nextTab: stepTab(1)
        case .previousTab: stepTab(-1)
        case .nextSpace: stepSpace(1)
        case .previousSpace: stepSpace(-1)
        case .newSpace: newSpace()
        case .newWindow:
            let tab = session.change { $0.openTab(nil, in: model.spaceID) }
            // Where no window can be made after all, the new tab comes up here.
            session.openWindow(space: model.spaceID, tab: tab) { [weak self] in
                guard let self, let tab else { return }
                show(tab: tab, inSpace: model.spaceID)
            }
        case .closeWindow:
            if let scene = view.window?.windowScene {
                UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            }
        case .tabBar: session.preferences.tabBar.toggle()
        case .diagnostics: session.preferences.diagnostics.toggle()
        case .settings: openSettings()
        case .focusPage:
            model.editingAddress = false
            refreshChrome()
            focusPage()
        case .pinTab:
            guard let tab = model.tabID, let record = session.workspace.tab(tab) else { return }
            session.change { record.isPinned ? $0.unpin(tab) : $0.pin(tab) }
        case .splitTab:
            guard let tab = model.tabID else { return }
            if session.workspace.split(containing: tab) != nil {
                session.change { $0.separate(tab) }
            } else {
                splitWithNewTab()
            }
        case .bookmark: toggleBookmark()
        case .share: sharePage()
        case .siteMode: switchSiteMode()
        case .contentBlocking: switchBlocking()
        case .linkMenu: switchOwnMenus()
        case .find: page?.find()
        case .handoff: handoff()
        case .history: openHistory()
        case .spaceSettings: openSpaceSettings(model.spaceID)
        case .importBookmarks: chooseBookmarksFile()
        }
    }

    /// A new tab beside the one on screen, typed into, as Dia's split.
    private func splitWithNewTab() {
        guard let tab = model.tabID, let new = Session.shared.change({ $0.splitWithNewTab(tab) }) else { return }
        show(tab: new, inSpace: model.spaceID)
        act(.editAddress)
    }

    /// `other` beside the tab on screen, on its right.
    private func split(with other: UUID) {
        let session = Session.shared
        guard let tab = model.tabID, session.change({ $0.split(tab, with: other) }) else { return }
        syncSplit()
        focusPage()
    }

    /// A new tab, and the command bar open for it with everything listed:
    /// an address or a search typed there goes in the new tab. A tab chosen
    /// is gone to instead, and a command runs on the page the bar was opened
    /// over, the new tab put away again either way (leave).
    private func newTab() {
        // Asked for again in the new tab's own bar (⌘T twice): the tab is
        // there already, still empty, so the bar only starts over.
        if let made = madeForBar, made.tab == model.tabID, Session.shared.workspace.tab(made.tab)?.url == nil {
            model.listsEverything = true
            act(.editAddress)
            return
        }
        let from = model.tabID
        guard let tab = Session.shared.change({ $0.openTab(nil, in: model.spaceID, after: from) }) else { return }
        show(tab: tab, inSpace: model.spaceID)
        model.listsEverything = true
        act(.editAddress)
        madeForBar = MadeTab(tab: tab, from: from)
    }

    /// The next tab along that no other window shows, going round; past
    /// the pinned tabs this device hides, as its row is.
    private func stepTab(_ direction: Int) {
        let session = Session.shared
        let shows = session.preferences.shows
        guard let current = model.tabID, let tabs = session.workspace.space(model.spaceID)?.tabs.filter(shows),
              tabs.count > 1 else { return }
        for offset in 1..<tabs.count {
            guard let next = session.workspace.neighbour(of: current, by: direction * offset, among: shows) else { return }
            // The pane beside is a step like any tab: it takes the keys.
            let shower = session.browser(showing: next)
            if shower == nil || shower === self {
                show(tab: next, inSpace: model.spaceID)
                return
            }
        }
    }

    private func stepSpace(_ direction: Int) {
        guard let next = Session.shared.workspace.spaceNeighbour(of: model.spaceID, by: direction),
              next != model.spaceID else { return }
        showSpace(next)
    }

    /// ⌃⌥1 to ⌃⌥8 the tab in that place in the row, ⌃⌥9 the last.
    private func selectTab(number: Int) {
        let session = Session.shared
        guard let tabs = session.workspace.space(model.spaceID)?.tabs.filter(session.preferences.shows), !tabs.isEmpty else { return }
        let index = number >= 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        show(tab: tabs[index].id, inSpace: model.spaceID)
    }

    private func newSpace() {
        let number = Session.shared.workspace.spaces.count + 1
        Dialogs.name(title: "New Space", message: "A space has its own tabs and its own sign-ins.",
                     placeholder: "Space \(number)", initial: "", on: presenter ?? self) { [weak self] name in
            guard let self, let name else { return }
            let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let space = Session.shared.change { $0.addSpace(named: chosen.isEmpty ? "Space \(number)" : chosen) }
            self.showSpace(space)
            self.act(.editAddress)
        }
    }

    private func removeSpace(_ id: UUID) {
        guard let space = Session.shared.workspace.space(id), Session.shared.workspace.spaces.count > 1 else { return }
        Dialogs.confirmRemoval(of: space.name, tabs: space.tabs.count, on: presenter ?? self) { sure in
            if sure { Session.shared.removeSpace(id) }
        }
    }

    /// Everything the bars and the empty space can ask for.
    func act(_ action: BarAction) {
        let session = Session.shared
        switch action {
        case .select(let tab): show(tab: tab, inSpace: session.workspace.spaceID(of: tab) ?? model.spaceID)
        case .close(let tab): session.closeTab(tab)
        case .closeTabs(let tabs): session.closeTabs(tabs)
        case .arrangeTabs(let arrangement): session.change { $0.arrangeTabs(in: model.spaceID, by: arrangement) }
        case .command(let command): perform(command)
        case .switchSpace(let space): showSpace(space)
        case .spaceInNewWindow(let space): session.openWindow(space: space, tab: nil)
        case .spaceSettings(let space): openSpaceSettings(space)
        case .removeSpace(let space): removeSpace(space)
        case .moveTab(let tab, let space): session.moveTab(tab, to: space)
        case .placeTab(let tab, let target):
            // A tab dragged from another window's space comes into this one's first, as the Mac's does.
            if let from = session.workspace.spaceID(of: tab), from != model.spaceID {
                session.moveTab(tab, to: model.spaceID)
            }
            // Where the target is once the dragged tab (and a split's other half) is out of the way.
            guard let space = session.workspace.space(model.spaceID) else { return }
            let moving = space.split(containing: tab).map { [$0.left, $0.right] } ?? [tab]
            guard !moving.contains(target),
                  let index = space.tabs.filter({ !moving.contains($0.id) }).firstIndex(where: { $0.id == target })
            else { return }
            session.change { $0.moveTab(tab, toIndex: index) }
        case .tabInNewWindow(let tab):
            // A tab goes to a window of its own alone; the pane beside it stays here.
            let beside = session.workspace.split(containing: tab)?.partner(of: tab)
            session.change { $0.separate(tab) }
            if model.tabID == tab {
                let next = beside ?? session.workspace.neighbour(of: tab, by: 1)
                let shower = next.flatMap { session.browser(showing: $0) }
                if let next, next != tab, shower == nil || shower === self {
                    show(tab: next, inSpace: model.spaceID)
                } else {
                    showEmpty(space: model.spaceID)
                }
            }
            // Where no window can be made after all, the tab comes back to this one.
            session.openWindow(space: session.workspace.spaceID(of: tab), tab: tab) { [weak self] in
                guard let self, let space = Session.shared.workspace.spaceID(of: tab) else { return }
                show(tab: tab, inSpace: space)
            }
        case .editAddress:
            model.editingAddress = true
            model.addressTurn += 1
            refreshChrome()
            awaitKeyboard()
        case .cancelAddress:
            model.editingAddress = false
            refreshChrome()
            focusPage()
        case .go(let text):
            // Read before typing ends, which lets the rows go.
            let chosen = model.suggestions.selected
            let made = madeForBar
            model.editingAddress = false
            if let chosen { take(chosen, leaving: made) } else { go(text) }
        case .suggestion(let row):
            let made = madeForBar
            model.editingAddress = false
            take(row, leaving: made)
        case .open(let url):
            open(url)
        case .back: page?.view.goBack()
        case .forward: page?.view.goForward()
        case .reload: page?.reload()
        case .stop: page?.view.stopLoading()
        case .dismissBanner:
            model.banner = nil
            refreshChrome()
        case .pin(let tab): session.change { _ = $0.pin(tab) }
        case .unpin(let tab): session.change { _ = $0.unpin(tab) }
        case .backToPinned(let tab): backToPinned(tab)
        case .openInNewTab(let url):
            guard let tab = session.change({ $0.openTab(url, in: model.spaceID, after: model.tabID) }) else { return }
            show(tab: tab, inSpace: model.spaceID)
        case .toggleBookmark: toggleBookmark()
        case .removeBookmark(let id): session.change { $0.removeBookmark(id, in: model.spaceID) }
        case .newFolder(let name, let parent): session.change { _ = $0.addFolder(named: name, in: parent, of: model.spaceID) }
        case .renameBookmark(let id, let name): session.change { $0.renameBookmark(id, to: name, in: model.spaceID) }
        case .moveBookmark(let id, let folder): session.change { $0.moveBookmark(id, into: folder, in: model.spaceID) }
        case .importBookmarks: chooseBookmarksFile()
        case .showTabs: showTabs()
        case .desktopView: toggleDesktopView()
        case .splitWith(let other): split(with: other)
        case .splitWithNewTab: splitWithNewTab()
        case .separate(let tab): session.change { $0.separate(tab) }
        case .swapSides(let tab): session.change { $0.swapSides(tab) }
        }
    }

    // MARK: Pinned tabs and bookmarks

    /// A pinned tab at the page it was pinned with: loaded there when it is
    /// live, its frozen picture of where it had gone let go when it isn't.
    private func backToPinned(_ tab: UUID) {
        let session = Session.shared
        guard let url = session.change({ $0.backToPinned(tab) }) else { return }
        HistoryRecorder.shared.expect(.bookmark, url)
        if let live = session.pages.live[tab] {
            live.load(url)
        } else {
            session.pages.close(tab)
        }
    }

    /// The page on screen as its desktop site, or its mobile one: kept for
    /// the site, and loaded again. A choice the window's size would make
    /// anyway isn't kept.
    private func switchSiteMode() {
        guard let page, let url = page.view.url, let key = SiteMode.siteKey(url.host) else { return }
        let wanted: SiteMode = page.mode == .desktop ? .mobile : .desktop
        let size = view.window?.bounds.size ?? view.bounds.size
        let natural = SiteMode.choose(host: nil, width: Double(size.width), height: Double(size.height), overrides: [:])
        Session.shared.preferences.siteModes[key] = wanted == natural ? nil : wanted
        page.reload(as: wanted)
    }

    /// Ads and trackers allowed or blocked on the site on screen, kept for
    /// the site, and the page loaded again with it. Not on a hands-off page,
    /// which the blocker never touches, nor with blocking off in Settings.
    private func switchBlocking() {
        guard let page, let host = page.view.url?.host, !page.isHandsOff, Session.shared.preferences.blocksContent else { return }
        let on = Session.shared.preferences.blocksContent(onHost: host)
        Session.shared.preferences.setBlocksContent(!on, onHost: host)
        page.reload()
        refreshChrome()
    }

    /// The site on screen keeps its own context menus, or gets the app's
    /// link menu: kept for the site. No reload: the app's menu asks as it
    /// opens, and the page that is up is told to keep callouts away or to
    /// let them be (Page.settingsChanged).
    private func switchOwnMenus() {
        guard let page, let host = page.view.url?.host, !page.isHandsOff else { return }
        let keeps = Session.shared.preferences.keepsOwnMenus(onHost: host)
        Session.shared.preferences.setKeepsOwnMenus(!keeps, onHost: host)
        refreshChrome()
    }

    // MARK: The iPhone's desktop view

    /// In: the page laid out at an iPad's size as its desktop site, the
    /// cursor over it (DesktopPad). Out: the page as the window's size has it.
    private func toggleDesktopView() {
        guard let page else { return }
        if page.desktopView {
            leaveDesktopView()
            return
        }
        guard Device.phone, page.view.url != nil, !page.isHandsOff else { return }
        page.desktopView = true
        if page.mode != .desktop { page.reload(as: .desktop) }
        showDesktopPad()
        refreshChrome()
    }

    private func leaveDesktopView() {
        guard let page, page.desktopView else { return }
        page.desktopView = false
        hideDesktopPad()
        let size = view.window?.bounds.size ?? view.bounds.size
        let natural = SiteMode.choose(host: page.view.url?.host, width: Double(size.width), height: Double(size.height),
                                      overrides: Session.shared.preferences.siteModes)
        if natural != page.mode { page.reload(as: natural) }
        refreshChrome()
    }

    /// The pad for the page on screen when it is in the desktop view; none otherwise.
    private func showDesktopPad() {
        guard let page, page.desktopView else { return hideDesktopPad() }
        if desktopPad?.page === page { return }
        hideDesktopPad()
        let pad = DesktopPad(page: page, size: stage.bounds.size)
        stage.addSubview(pad)
        desktopPad = pad
        layoutPanes()
    }

    private func hideDesktopPad() {
        guard let pad = desktopPad else { return }
        desktopPad = nil
        pad.leave()
        layoutPanes()
    }

    /// Shows the space's tabs as a grid, from the phone bar's Tabs button:
    /// the bar turns into them, as a swipe up on it does.
    private func showTabs() {
        guard presentedViewController == nil else { return }
        makeTabSheet()?.open()
    }

    /// The sheet of tabs over the page, under the bar it grows out of; the
    /// one there already when the bar is caught on its way.
    private func makeTabSheet() -> TabSheet? {
        if let tabSheet { return tabSheet }
        guard model.phone, let bar = phoneBar?.view, !bar.isHidden else { return nil }
        let overview = TabOverviewController(session: Session.shared, window: model, act: { [weak self] action in
            self?.act(action)
        }, done: { [weak self] action in
            self?.closeTabs(then: action)
        })
        let sheet = TabSheet(content: overview, bar: bar)
        sheet.closed = { [weak self] in self?.tabSheetClosed() }
        addChild(sheet)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(sheet.view, belowSubview: bar)
        sheet.didMove(toParent: self)
        tabSheet = sheet
        return sheet
    }

    /// Done with the tabs. A tab goes on screen as the sheet goes, so the
    /// bar sinks back onto it; anything else waits until the bar is back.
    private func closeTabs(then action: BarAction?) {
        if let action, case .select = action { act(action) } else { afterTabs = action }
        tabSheet?.close()
    }

    private func tabSheetClosed() {
        guard let sheet = tabSheet else { return }
        sheet.willMove(toParent: nil)
        sheet.view.removeFromSuperview()
        sheet.removeFromParent()
        tabSheet = nil
        if let bar = phoneBar?.view {
            bar.transform = .identity
            bar.alpha = 1
            bar.isUserInteractionEnabled = true
        }
        if let action = afterTabs {
            afterTabs = nil
            act(action)
        } else {
            focusPage()
        }
    }

    /// The page on screen, through the system's share sheet. The web view
    /// goes in with its address: for a browser with Apple's entitlement, that
    /// is what puts Add to Home Screen in the sheet, so a web app gets its
    /// own icon on the Home Screen.
    /// The page's address goes without the tags that follow whoever opens
    /// it (Tracking.clean); the page itself goes too, for Add to Home Screen.
    private func sharePage() {
        guard let page, let url = page.view.url else { return }
        share([Tracking.clean(url), page.view])
    }

    func page(_ page: Page, share url: URL) {
        share([Tracking.clean(url)])
    }

    var opensTabs: Bool {
        true
    }

    /// Handoff: the page on screen as a Markdown file, with the question
    /// and the page's address beside it, through the share sheet, where the
    /// app to read them is picked (Handoff.swift). Nothing of the page goes
    /// anywhere before that. A page with nothing to read as text (a
    /// picture, a PDF) goes as the words alone, which say where it is.
    ///
    /// A sheet says what Handoff does and how far it is (HandoffGuide),
    /// while the page is read, its file written and, where Apple
    /// Intelligence's model is there, the model asked (HandoffJob). The
    /// share sheet comes only at the sheet's own button, which is to be
    /// had once the file is as it will go.
    private func handoff() {
        guard Session.shared.preferences.handoff, Session.shared.hasIntelligence, presentedViewController == nil, !startsHandoff,
              let page, !page.isHandsOff else { return }
        handingOff?.finish(taken: false)
        handingOff = nil
        startsHandoff = true
        Task { [weak self, weak page] in
            // Whether the model is there to ask, known before the sheet says who organises the page.
            let mind = await PageMinds.mind()
            guard let self else { return }
            self.startsHandoff = false
            // Asked after the wait: the page may have gone, or something come up over it.
            guard let page, self.page === page, !page.isHandsOff, let url = page.view.url,
                  self.presentedViewController == nil else { return }
            let job = HandoffJob(page: page, url: url, title: page.view.title ?? "", mind: mind)
            self.handingOff = job
            self.explain(job)
        }
    }

    /// The share sheet for a handoff: the file (HandoffFile) and the words beside it.
    private func share(_ job: HandoffJob) {
        guard handingOff === job else { return }
        share(job.stage.hasFile ? [HandoffFile(job), job.prompt] : [job.prompt]) { [weak self] taken in
            // Not taken by any app: nothing is left behind.
            job.finish(taken: taken)
            if self?.handingOff === job { self?.handingOff = nil }
        }
    }

    /// What Handoff does, as a sheet over the page while it is made ready
    /// (HandoffGuide). Its button goes on to the share sheet; put away any
    /// other way, the handoff is off.
    private func explain(_ job: HandoffJob) {
        guard presentedViewController == nil else {
            // Something else came up over the page meanwhile: the handoff is off.
            job.finish(taken: false)
            handingOff = nil
            return
        }
        let colour = Session.shared.workspace.space(model.spaceID)?.color ?? .blue
        // From the bottom edge on a phone-width window, over the home indicator's room where the device has one.
        let stands = traitCollection.horizontalSizeClass == .compact && (view.window?.safeAreaInsets.bottom ?? 0) > 0
        var went = false
        let guide = UIHostingController(rootView: HandoffGuide(job: job, colour: colour, foot: stands ? 0 : HandoffGuide.edge) { [weak self] in
            guard !went else { return }
            went = true
            self?.guideClosed = nil
            self?.dismiss(animated: true) { self?.share(job) }
        })
        guide.view.backgroundColor = Palette.UI.ground
        guide.modalPresentationStyle = .formSheet
        // As high as what it says, on a phone from the bottom edge.
        let width = min(view.bounds.width, 480)
        let height = guide.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        guide.preferredContentSize = CGSize(width: width, height: height)
        if let sheet = guide.sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("guide")) { context in min(height, context.maximumDetentValue) }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = HandoffGuide.corner
        }
        guideClosed = { [weak self] in
            guard !went else { return }
            went = true
            job.finish(taken: false)
            if self?.handingOff === job { self?.handingOff = nil }
        }
        guide.presentationController?.delegate = self
        present(guide, animated: true)
    }

    /// `done` hears whether the sheet ended with something taken.
    private func share(_ items: [Any], done: ((Bool) -> Void)? = nil) {
        guard presentedViewController == nil else {
            done?(false)
            return
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // From the bar the address is in: the address bar, or the row of tabs,
        // or the sidebar, under its page menu (SideTabs).
        if let popover = sheet.popoverPresentationController,
           let anchor = [phoneBar?.view, addressBar?.view, topBar?.view, sideTabs?.view, view].compactMap({ $0 })
               .first(where: { !$0.isHidden }) {
            popover.sourceView = anchor
            // Under a bar at the top; over the one at the bottom on a phone-width window.
            let below = anchor !== phoneBar?.view
            popover.sourceRect = anchor === sideTabs?.view
                ? CGRect(x: anchor.bounds.maxX - 28, y: Metrics.target - 4, width: 1, height: 1)
                : CGRect(x: anchor.bounds.midX, y: below ? anchor.bounds.maxY - 6 : anchor.bounds.minY + 6,
                         width: 1, height: 1)
            popover.permittedArrowDirections = below ? .up : .down
        }
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            done?(completed)
            self?.focusPage()
        }
        present(sheet, animated: true)
    }

    /// The page on screen into the space's bookmarks, or out of them.
    private func toggleBookmark() {
        guard let page, let url = page.view.url else { return }
        let session = Session.shared
        let space = model.spaceID
        if let known = session.workspace.bookmark(for: url, in: space) {
            session.change { $0.removeBookmark(known.id, in: space) }
        } else {
            session.change { $0.addBookmark(url, title: page.view.title ?? "", in: space) }
        }
        refreshChrome()
    }

    /// A bookmarks file for this window's space, from Files: Chrome's or
    /// Firefox's export, Safari's Bookmarks.html, or the ZIP Safari's
    /// Export Browsing Data saves to Downloads.
    func chooseBookmarksFile() {
        guard presentedViewController == nil else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.html, .zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let file = urls.first else { return }
        Session.shared.importBookmarks(from: file, into: model.spaceID) { [weak self] outcome in
            // The picker's copy, done with once it has been read.
            try? FileManager.default.removeItem(at: file)
            guard let self else { return }
            let alert = UIAlertController(title: outcome.title, message: outcome.message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.focusPage() })
            present(alert, animated: true)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        focusPage()
    }

    /// The space's history (HistoryView), as a sheet; a page chosen there opens here.
    func openHistory() {
        guard presentedViewController == nil else { return }
        let history = UIHostingController(rootView: HistoryView(spaceID: model.spaceID) { [weak self] url, newTab in
            guard let self else { return }
            if newTab, let tab = Session.shared.change({ $0.openTab(url, in: self.model.spaceID) }) {
                self.show(tab: tab, inSpace: self.model.spaceID)
            } else {
                self.open(url)
            }
        } done: { [weak self] in
            self?.dismiss(animated: true) { self?.focusPage() }
        })
        history.modalPresentationStyle = .formSheet
        history.presentationController?.delegate = self
        present(history, animated: true)
    }

    func openSpaceSettings(_ space: UUID) {
        guard presentedViewController == nil else { return }
        let editor = UIHostingController(rootView: NavigationStack {
            SpaceEditor(session: Session.shared, spaceID: space) { [weak self] in
                self?.dismiss(animated: true) { self?.focusPage() }
            }
        })
        editor.modalPresentationStyle = .formSheet
        editor.presentationController?.delegate = self
        present(editor, animated: true)
    }

    /// A row the address bar offered, chosen with Return or a tap. `made`
    /// is the new tab the bar was opened for, if it was.
    private func take(_ row: Suggestion, leaving made: MadeTab? = nil) {
        switch row.action {
        case .tab(let tab):
            refreshChrome()
            act(.select(tab))
            leave(made)
            focusPage()
        case .open(let url):
            HistoryRecorder.shared.expect(.typed, url)
            open(url)
        case .space(let space):
            refreshChrome()
            showSpace(space)
            leave(made)
            focusPage()
        case .command(let command):
            // New Tab taken in a new tab's own bar: the tab is there already.
            if command == .newTab, made != nil {
                refreshChrome()
                focusPage()
                return
            }
            // A command is for the page the bar was opened over (Reload Page,
            // Pin or Unpin Tab), not for the empty tab made to type in.
            leave(made)
            // The field is put away first: a command may open one again (New Tab).
            refreshChrome()
            perform(command)
            focusPage()
        case .setting(let anchor):
            leave(made)
            refreshChrome()
            openSettings(at: anchor)
        case .go(let text):
            go(text)
        }
    }

    /// The new tab the command bar was opened for is closed again when the
    /// row taken wasn't an address for it: nothing was ever asked of it,
    /// and it would be left behind empty. A window still on it (a command
    /// was taken, or a tab that another window has up) goes back first to
    /// the tab the bar was opened from.
    private func leave(_ made: MadeTab?) {
        let session = Session.shared
        guard let made, session.workspace.tab(made.tab)?.url == nil else { return }
        if model.tabID == made.tab, let from = made.from, session.workspace.tab(from) != nil {
            show(tab: from, inSpace: model.spaceID)
        }
        // With nowhere to go back to, closing it takes the window to its neighbour.
        session.closeTab(made.tab)
    }

    /// A typed line: an address, or a search with the chosen engine.
    private func go(_ text: String) {
        guard let url = Destination.url(for: text, engine: Session.shared.preferences.engine) else {
            refreshChrome()
            focusPage()
            return
        }
        HistoryRecorder.shared.expect(.typed, url)
        open(url)
    }

    /// A link from another app, or from any app once Safience is the default
    /// browser: a tab of its own after this one, so the page it lands on top
    /// of (a Figma file, a message half written) stays as it was.
    func openLink(_ url: URL) {
        guard let tab = Session.shared.change({ $0.openTab(url, in: model.spaceID, after: model.tabID) }) else { return }
        show(tab: tab, inSpace: model.spaceID)
    }

    /// An address, in this window's tab, or in a new tab when there is none.
    func open(_ url: URL) {
        if let page {
            page.load(url)
        } else if let tab = Session.shared.change({ $0.openTab(url, in: model.spaceID) }) {
            show(tab: tab, inSpace: model.spaceID)
        }
        model.editingAddress = false
        refreshChrome()
        focusPage()
    }

    // MARK: Settings

    /// Settings, from its top; or at one of its parts, which the address
    /// bar finds by name ("change icon" for App Icon).
    func openSettings(at anchor: SettingsAnchor? = nil) {
        guard presentedViewController == nil else { return }
        let layouts = Device.settingsLayouts(compact: model.phone)
        let settings = UIHostingController(rootView: SettingsView(session: Session.shared, spaceID: model.spaceID,
                                                                  anchor: anchor, phoneLayout: layouts.phone,
                                                                  padLayout: layouts.pad) { [weak self] in
            self?.dismiss(animated: true) { self?.focusPage() }
        })
        settings.modalPresentationStyle = .formSheet
        settings.presentationController?.delegate = self
        present(settings, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Swiped away, or tapped outside of: the handoff's guide says so.
        guideClosed?()
        guideClosed = nil
        focusPage()
    }
}

/// The tab beside, as it comes in while the phone bar is dragged sideways:
/// the picture it was last seen as, or its site's icon on the page's ground
/// where there is none yet.
private final class SlideCard: UIView {
    let tab: TabRecord

    init(tab: TabRecord, picture: UIImage?) {
        self.tab = tab
        super.init(frame: .zero)
        backgroundColor = Palette.UI.ground
        clipsToBounds = true
        isUserInteractionEnabled = false
        if let picture {
            show(picture)
        } else if tab.url != nil {
            let icon = SiteIconUIView()
            icon.size = 44
            icon.url = tab.url
            icon.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            icon.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            addSubview(icon)
            self.icon = icon
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    private var icon: UIView?

    /// The tab's picture, over the icon that stood in for it.
    /// The picture, read from disk while the finger drags: it fades in over
    /// the site's icon rather than replacing it in one frame mid-gesture.
    func show(_ picture: UIImage) {
        let image = UIImageView(image: picture)
        image.contentMode = .scaleAspectFill
        image.frame = bounds
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        image.alpha = 0
        addSubview(image)
        let icon = icon
        self.icon = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction]) {
            image.alpha = 1
        } completion: { _ in
            icon?.removeFromSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A little above the middle, where the page's own content would start to show.
        icon?.center = CGPoint(x: bounds.midX, y: bounds.height * 0.4)
    }
}

/// The phone bar's swipe, up or sideways. SwiftUI's buttons would otherwise prevent it
/// whenever it starts on one of them, which on the bar is nearly always.
private final class BarSwipe: UIPanGestureRecognizer {
    override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool {
        false
    }

    override func shouldRequireFailure(of other: UIGestureRecognizer) -> Bool {
        false
    }
}

/// Where the pages are. It lays them out itself when its size changes: the
/// window's own layout comes before the stack has given it its new size,
/// and a page sized then kept the height it had over the keyboard.
/// The window's own view. UIKit runs a view's updateConstraints() again
/// when the reserved regions read in it change, as the iPhone Duo folds
/// and opens: the Browser lays its sidebar out to the fold from there.
private final class BrowserView: UIView {
    var constraintsUpdated: (() -> Void)?

    override func updateConstraints() {
        constraintsUpdated?()
        super.updateConstraints()
    }
}

private final class Stage: UIView {
    var laidOut: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        laidOut?()
    }
}
