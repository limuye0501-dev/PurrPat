import simd
import SwiftUI
import UIKit

@MainActor
struct PetScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var purchases: PurchaseManager
    @StateObject private var session = PetSession()
    @State private var feedback = PurrFeedback()
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var paywallAfterSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                CatCanvas(session: session, settings: settings)
                    .ignoresSafeArea()
                    .gesture(drag(in: size))
                if settings.handEnabled, let anchor = session.handAnchor, session.handOpacity > 0.02 {
                    handShadow(at: anchor, in: size)
                        .opacity(session.handOpacity * 0.9)
                    hand(at: anchor, in: size)
                        .opacity(session.handOpacity)
                }
                heart(in: size)
                controls(insets: geo.safeAreaInsets)
            }
            .onAppear { session.placeDemoHand(in: size, settings: settings) }
            .onChange(of: size) { _, newSize in
                session.placeDemoHand(in: newSize, settings: settings)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(settings.scene == .night ? .dark : .light)
        .onAppear(perform: appear)
        .onChange(of: scenePhase) { _, phase in
            feedback.setActive(phase == .active)
        }
        .onChange(of: purchases.isPro) { _, pro in
            settings.clamp(isPro: pro)
        }
        .onChange(of: settings.rain) { _, on in
            feedback.setRain(on: on)
        }
        .onChange(of: settings.purrEnabled) { _, _ in
            feedback.setPurr(enabled: settings.purrEnabled, level: Float(session.purrLevel))
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if paywallAfterSettings {
                paywallAfterSettings = false
                showPaywall = true
            }
        }) {
            SettingsView {
                paywallAfterSettings = true
                showSettings = false
            }
            .environmentObject(settings)
            .environmentObject(purchases)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(purchases)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func appear() {
        settings.clamp(isPro: purchases.isPro)
        session.installDemo(settings: settings, purchases: purchases)
        session.onLevels = { level, enabled in
            feedback.setPurr(enabled: enabled && settings.purrEnabled, level: Float(level))
        }
        session.onDelight = { feedback.playDelight() }
        guard !DemoShot.underTest else { return }
        purchases.start()
        feedback.start()
        feedback.setRain(on: settings.rain)
        if DemoShot.current == .paywall {
            showPaywall = true
        }
        if DemoShot.current?.frozen == true {
            UIView.setAnimationsEnabled(false)
        }
        session.placeDemoHand(in: UIScreen.main.bounds.size, settings: settings)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                session.pointer(at: value.location, in: size, settings: settings, when: CACurrentMediaTime())
            }
            .onEnded { _ in
                session.pointerEnded()
            }
    }

    /// Palm about as wide as the cat's head, and always long enough that the sleeve leaves the bottom edge.
    private func handMetrics(at fingertip: CGPoint, in size: CGSize) -> (width: CGFloat, height: CGFloat, center: CGPoint, angle: CGFloat) {
        let fit = CatLayout.fitRect(in: size, catSize: settings.catSize)
        let head = (CatLayout.catMaxX - CatLayout.catMinX) * 0.55 * fit.width
        var width = head / HandStyle.knuckleFraction
        var height = width / HandStyle.aspect
        let reach = (size.height - fingertip.y + 48) / (1 - HandStyle.anchor.y)
        if height < reach {
            height = reach
            width = height * HandStyle.aspect
        }
        let anchor = HandStyle.anchor
        let center = CGPoint(
            x: fingertip.x - (anchor.x - 0.5) * width,
            y: fingertip.y - (anchor.y - 0.5) * height
        )
        let angle = HandStyle.sleeveDown + session.handAngle
        return (width, height, center, angle)
    }

    private func hand(at fingertip: CGPoint, in size: CGSize) -> some View {
        let metrics = handMetrics(at: fingertip, in: size)
        let anchor = HandStyle.anchor
        return Image(settings.handStyle.assetName)
            .resizable()
            .renderingMode(.original)
            .frame(width: metrics.width, height: metrics.height)
            .rotationEffect(.radians(metrics.angle), anchor: UnitPoint(x: anchor.x, y: anchor.y))
            .position(metrics.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func handShadow(at fingertip: CGPoint, in size: CGSize) -> some View {
        let metrics = handMetrics(at: fingertip, in: size)
        let palm = metrics.width * HandStyle.knuckleFraction
        return Ellipse()
            .fill(Color.black.opacity(0.38))
            .frame(width: palm * 1.25, height: palm * 0.42)
            .blur(radius: palm * 0.18)
            .rotationEffect(.radians(metrics.angle * 0.35))
            .position(x: fingertip.x, y: fingertip.y + palm * 0.22)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func heart(in size: CGSize) -> some View {
        let point = CatLayout.point(SIMD2(0.30, 0.38), in: size, catSize: settings.catSize)
        let opacity = max(session.purrLevel * 0.65, max(0, (session.happiness - 0.28) * 1.35))
        return Image(systemName: "heart.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color(red: 0.86, green: 0.34, blue: 0.38))
            .scaleEffect(1 + session.purrLevel * 0.12)
            .opacity(opacity)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func controls(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                chrome("square.and.arrow.up", "Share") { share() }
                chrome(settings.purrEnabled ? "waveform" : "speaker.slash", "Purr") {
                    settings.purrEnabled.toggle()
                }
                if settings.scene == .night {
                    chrome("sun.max", "Daylight") { settings.scene = .day }
                } else {
                    chrome("moon.stars", "Moonlight") { toggleScene() }
                }
                chrome("gearshape", "Settings") { showSettings = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 8)
            Spacer()
            if !settings.hasStroked && DemoShot.current == nil {
                Text("Stroke with the fur")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
            coatBar
                .padding(.bottom, insets.bottom + 8)
        }
    }

    private var coatBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Coat.allCases) { coat in
                    let locked = !Entitlement.coatUnlocked(coat, isPro: purchases.isPro)
                    Button {
                        if locked { showPaywall = true } else { settings.coat = coat }
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: PlateLibrary.shared.swatch(coat))
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(settings.coat == coat ? 0.95 : 0), lineWidth: 2.5)
                                }
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            if locked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .offset(x: 2, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(coat.title))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }

    private func chrome(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func toggleScene() {
        if settings.scene == .night {
            settings.scene = .day
            return
        }
        if purchases.isPro {
            settings.scene = .night
        } else {
            showPaywall = true
        }
    }

    private func share() {
        let bounds = UIScreen.main.bounds
        let image = ScenePainter.render(
            bounds: bounds.size,
            scale: min(UIScreen.main.scale, 2),
            coat: settings.coat,
            scene: settings.scene,
            pose: session.pose,
            groom: session.groom,
            rain: settings.rain ? 1 : 0,
            time: Float(session.time),
            catSize: settings.catSize,
            interactive: false
        )
        let caption = String(localized: "A still from Purr Pat")
        let controller = UIActivityViewController(activityItems: [image, caption], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.minY + 80, width: 1, height: 1)
            pop.permittedArrowDirections = .up
        }
        top.present(controller, animated: true)
    }
}
