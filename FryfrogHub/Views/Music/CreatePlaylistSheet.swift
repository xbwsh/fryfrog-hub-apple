import SwiftUI

struct CreatePlaylistSheet: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var comment = ""
    @State private var isPublic = false
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("备注（可选）", text: $comment)
                    Toggle("公开", isOn: $isPublic)
                } header: {
                    Text("歌单信息")
                } footer: {
                    if isPublic {
                        Label("公开后，所有登录用户可在“歌单”列表看到该歌单，可查看并播放其中的歌曲（无法修改）。他人将能看到歌单名称、备注及创建者昵称，请勿包含隐私内容。", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("私有歌单仅自己可见，他人无法查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("新建歌单").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                _ = try await MusicService.shared.createPlaylist(name: name, comment: comment.isEmpty ? nil : comment, isPublic: isPublic, songIds: [])
                                GlobalNotice.shared.show("已创建“\(name)”")
                                await onCreated()
                                dismiss()
                            } catch { GlobalNotice.shared.show("创建失败：\(error.localizedDescription)") }
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}
