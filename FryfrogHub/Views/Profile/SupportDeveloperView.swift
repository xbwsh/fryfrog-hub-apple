import SwiftUI

// MARK: - 支持开发者

/// 打赏渠道配置（替换为你的实际收款码 / 爱发电主页）
enum SupportConfig {
    /// 爱发电主页链接
    static let afdianURLString = "https://afdian.com"
    /// 微信收款码图片名（Assets.xcassets/WechatReward.imageset 内放入 WechatReward.png）
    static let wechatRewardImage = "WechatReward"
    /// 支付宝收款码图片名（Assets.xcassets/AlipayReward.imageset 内放入 AlipayReward.png）
    static let alipayRewardImage = "AlipayReward"
}

/// 支持作者页：扫码打赏（微信/支付宝）+ 爱发电跳转
struct SupportDeveloperView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fryfrog Hub 是你自己的媒体库客户端，如果你觉得好用，欢迎打赏支持独立开发者 ☕")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("扫码打赏") {
                NavigationLink {
                    RewardQRView(imageName: SupportConfig.wechatRewardImage, title: "微信")
                } label: {
                    Label("微信", systemImage: "circle.hexagongrid.fill")
                        .foregroundStyle(.green)
                }
                NavigationLink {
                    RewardQRView(imageName: SupportConfig.alipayRewardImage, title: "支付宝")
                } label: {
                    Label("支付宝", systemImage: "circle.circle")
                        .foregroundStyle(.blue)
                }
            }

            Section("爱发电") {
                Button {
                    openAfdian()
                } label: {
                    Label("在爱发电支持", systemImage: "bolt.heart.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("支持开发者")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openAfdian() {
        guard let url = URL(string: SupportConfig.afdianURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 收款码页面：展示二维码图（未配置时显示占位提示）
struct RewardQRView: View {
    let imageName: String
    let title: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 280, height: 280)
                    .overlay {
                        Text("\(title)收款码待配置")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            }

            Text("长按识别图中二维码即可打赏")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("如何替换收款码：")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("把二维码图片放入 WechatReward.imageset / AlipayReward.imageset")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
