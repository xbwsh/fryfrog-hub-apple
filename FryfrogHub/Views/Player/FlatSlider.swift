import SwiftUI
import UIKit

/// 扁平化进度滑杆：UISlider + 自绘无阴影圆点 thumb，与控制栏纯色图标风格统一
/// （系统 SwiftUI Slider 的滑块带投影，与周围扁平控件视觉不一致）
struct FlatSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        // 已播段主题青色（对齐 Web 原型 --accent）
        slider.minimumTrackTintColor = UIColor(red: 0, green: 0.784, blue: 0.706, alpha: 1)
        // 未播轨道白色 24%
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.24)
        slider.setThumbImage(Self.thumbImage, for: .normal)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingBegan(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        // 拖动中由手势驱动，不覆盖当前值
        if !context.coordinator.isEditing {
            slider.setValue(Float(value), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 白色圆点滑块（柔和投影，对齐 Web 原型 progress-dot）。
    /// 画布放大到 24pt 给投影留空间；renderer 默认 opaque=true 会垫黑底（就是看到的"黑底"），必须关掉
    private static let thumbImage: UIImage = {
        let canvas: CGFloat = 24
        let circle: CGFloat = 12
        let inset = (canvas - circle) / 2
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: format)
        return renderer.image { ctx in
            ctx.cgContext.setShadow(
                offset: .zero, blur: 4, color: UIColor.black.withAlphaComponent(0.6).cgColor
            )
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: circle, height: circle)).fill()
        }
    }()

    final class Coordinator: NSObject {
        private let parent: FlatSlider
        var isEditing = false

        init(_ parent: FlatSlider) { self.parent = parent }

        @objc func valueChanged(_ slider: UISlider) {
            parent.value = Double(slider.value)
        }

        @objc func editingBegan(_ slider: UISlider) {
            isEditing = true
            parent.onEditingChanged(true)
        }

        @objc func editingEnded(_ slider: UISlider) {
            isEditing = false
            parent.onEditingChanged(false)
        }
    }
}
