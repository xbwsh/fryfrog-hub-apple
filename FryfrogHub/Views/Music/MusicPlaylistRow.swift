import SwiftUI

struct MusicPlaylistRow: View {
    let playlist: MusicPlaylist
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "music.note.list").foregroundStyle(Color.accentColor).font(.title3)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if let c = playlist.comment, !c.isEmpty {
                            Text(c).lineLimit(1)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        if playlist.isPublic == true {
                            HStack(spacing: 4) {
                                Label("公开", systemImage: "globe")
                                if playlist.userId != AuthService.shared.currentUser?.id {
                                    Text("他人").foregroundStyle(.orange)
                                }
                            }
                            .font(.caption2)
                        } else {
                            Label("私有", systemImage: "lock").font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary).font(.caption).lineLimit(1)
                    if playlist.isPublic == true, playlist.userId != AuthService.shared.currentUser?.id, let uid = playlist.userId {
                        Text("创建者 ID: \(uid)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
