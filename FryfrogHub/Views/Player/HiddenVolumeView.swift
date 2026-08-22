import SwiftUI
import UIKit
import MediaPlayer

/// 隐藏的 MPVolumeView：抓取其内部 UISlider，用于手势程序化调整系统音量
/// 注意：不能 isHidden=true（隐藏时内部不创建 MPVolumeSlider），
/// 改为屏幕外 + 透明 + 禁交互，并等系统初始化后抓取
struct HiddenVolumeView: UIViewRepresentable {
    let onSliderReady: (UISlider) -> Void

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        view.isHidden = false
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        // 等系统初始化音频组件后，subviews 才包含 MPVolumeSlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
                MPVLog.log("volume slider ready value=\(slider.value)")
                onSliderReady(slider)
            } else {
                MPVLog.log("volume slider NOT FOUND")
            }
        }
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
