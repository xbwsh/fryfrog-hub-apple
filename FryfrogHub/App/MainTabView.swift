import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var auth = AuthService.shared

    enum Tab {
        case home, music, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(Tab.home)

            MusicView()
                .tabItem {
                    Label("音乐", systemImage: "music.note.list")
                }
                .tag(Tab.music)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
    }
}
