import SwiftUI

/// 成人内容模糊遮挡修饰符：隐私模式开启时对受保护内容打码
struct PrivacyProtectedModifier: ViewModifier {
    let isProtected: Bool

    private var privacy: PrivacySettings { .shared }

    private var shouldBlur: Bool {
        privacy.isEnabled && isProtected
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: shouldBlur ? 12 : 0)
            .overlay {
                if shouldBlur {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.2), value: shouldBlur)
    }
}

extension View {
    /// 隐私模式开启且为成人内容时，自动模糊遮挡
    func privacyProtected(_ isProtected: Bool) -> some View {
        modifier(PrivacyProtectedModifier(isProtected: isProtected))
    }
}

/// 隐私遮罩：App 切到后台/多任务时盖住整个界面，防止内容预览泄露
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color.appBackground
            VStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.largeTitle)
                Text("隐私模式已开启")
                    .font(.subheadline)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
