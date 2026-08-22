import SwiftUI

/// 追更日历：在播剧集的下一集播出日期，按日期分组展示
struct CalendarView: View {
    @State private var items: [CalendarItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var privacy: PrivacySettings { .shared }
    private var client: APIClient { .shared }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "暂无追更",
                    systemImage: "calendar",
                    description: Text(errorMessage ?? "没有在播且已排期的剧集")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedDates) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatDate(group.date))
                                    .font(.headline)
                                ForEach(group.items) { item in
                                    calendarRow(item)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("追更日历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: ApiResponse<[CalendarItem]> = try await client.request("/api/v1/video/series/calendar")
            let all = response.data ?? []
            // 隐私模式下隐藏成人内容（日历接口无 isAdult 字段，通过首页分库数据交叉识别）
            items = privacy.isEnabled
                ? all.filter { !adultSeriesIds.contains($0.seriesId) }
                : all
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 首页已加载的分库数据中标记为成人的系列 ID（isAdult 或含成人剧集）
    private var adultSeriesIds: Set<Int64> {
        var ids = Set<Int64>()
        for group in HomeService.shared.groups {
            let items = group.allItems
            let groupIsAdult = items.contains { $0.isAdult == true || $0.hasAdultEpisodes == true }
            if groupIsAdult {
                ids.formUnion(items.map(\.id))
            }
        }
        return ids
    }

    /// 服务端已按日期升序返回，按日期顺序分组成段
    private var groupedDates: [DateGroup] {
        var result: [DateGroup] = []
        for item in items {
            let date = item.nextEpisodeDate ?? "待定"
            if var last = result.last, last.date == date {
                result[result.count - 1].items.append(item)
            } else {
                result.append(DateGroup(date: date, items: [item]))
            }
        }
        return result
    }

    /// "2026-08-15" → "今天" / "明天" / "8月15日 周六"（跨年时带年份）
    private func formatDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let target = DateComponents(calendar: .current, year: year, month: month, day: day).date else {
            return date
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(target) {
            return "今天"
        }
        if calendar.isDateInTomorrow(target) {
            return "明天"
        }

        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdays[calendar.component(.weekday, from: target) - 1]
        if calendar.component(.year, from: target) != calendar.component(.year, from: Date()) {
            return "\(year)年\(month)月\(day)日 \(weekday)"
        }
        return "\(month)月\(day)日 \(weekday)"
    }

    // MARK: - 行

    private func calendarRow(_ item: CalendarItem) -> some View {
        NavigationLink {
            // 从日历进入时自动定位到下一集所在季
            SeriesDetailView(
                series: item.seriesListDTO,
                onFavoriteChanged: { _ in Task { await load() } },
                initialSeason: item.nextSeasonNumber
            )
        } label: {
            HStack(spacing: 12) {
                ServerImageView(path: item.coverUrl)
                    .frame(width: 56, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.episodeLabel.isEmpty {
                        Text("下一集 \(item.episodeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// 同一天期的剧集分组
private struct DateGroup: Identifiable {
    let date: String
    var items: [CalendarItem]

    var id: String { date }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
}
