import SwiftUI
import UIKit

// MARK: - 设计令牌（Design Tokens）
// 统一深色页面背景为柔和黑灰而非常规纯黑，观感更高级。

/// 在深色下返回柔和黑灰，浅色下返回系统默认
private func adaptiveDark(_ rgb: (Double, Double, Double)) -> Color {
    Color(uiColor: adaptiveDarkUIColor(rgb))
}

/// 与 adaptiveDark 同源的 UIColor（用于设置 UIWindow 背景，防止内容未覆盖区域露出纯黑）
private func adaptiveDarkUIColor(_ rgb: (Double, Double, Double)) -> UIColor {
    UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        default:
            return .systemBackground
        }
    }
}

extension UIColor {
    /// 与 Color.appBackground 同色
    static let appBackground = adaptiveDarkUIColor((0.11, 0.12, 0.15))
}

extension Color {
    /// 需要完全遮挡内容时使用的纯黑色背景（隐私遮罩/视频画布）。
    static let appBlack = Color.black

    /// 页面主背景（柔和黑灰 / 系统白）
    static let appBackground = adaptiveDark((0.11, 0.12, 0.15))

    /// 次级背景 / 卡片表面（深色比主背景亮一档形成层次；浅色用浅灰与白底区分，保证卡片轮廓可见）
    static let appSurface = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        default:
            return UIColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        }
    })

}

/// 统一的全屏加载状态，避免局部 ProgressView 让容器背景露出纯黑。
struct AppLoadingView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ProgressView(title)
                .tint(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
