import SwiftUI

/// 海报卡片（竖版封面 + 标题 + 评分）
struct PosterCard: View {
    let item: SeriesListDTO

    private var privacy: PrivacySettings { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                ServerImageView(path: item.coverUrl)
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .privacyProtected(privacy.isEnabled && item.isAdult == true)

                // 分辨率叠加在封面右下角（多个分辨率都显示，空格分隔）
                if let resolutions = item.resolutions, !resolutions.isEmpty {
                    Text(resolutions.joined(separator: " "))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }

                // 评分叠加在封面左上角
                if let rating = item.rating, rating > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
                }
            }
            .frame(width: 120)

            Text(item.displayTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 4) {
                if item.isAdult == true {
                    Text("18+")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 120, alignment: .leading)
        }
    }
}
