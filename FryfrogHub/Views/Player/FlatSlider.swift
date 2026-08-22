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
        slider.minimumTrackTintColor = .white
        // 未播轨道调暗，让叠加的已缓冲区域（白 30%）可区分
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.15)
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

    /// 14pt 白色圆点滑块（无投影）
    private static let thumbImage: UIImage = {
        let size: CGFloat = 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
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
