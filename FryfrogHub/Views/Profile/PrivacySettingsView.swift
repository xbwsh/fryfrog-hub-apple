import SwiftUI

struct PrivacySettingsView: View {
    @Bindable private var privacy = PrivacySettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("隐私模式", isOn: $privacy.isEnabled)
            } footer: {
                Text("开启后，成人内容将在首页、收藏、日历中隐藏，海报与封面会被模糊遮挡；离开 App 时界面将被遮罩，多任务切换不显示内容预览。")
            }

            Section {
                Toggle("局域网自动关闭隐私模式", isOn: $privacy.autoDisableOnLAN)
            } footer: {
                Text("开启后，当检测到局域网连接时自动关闭隐私模式；在外网环境下需手动重新开启。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("隐私模式")
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
}
