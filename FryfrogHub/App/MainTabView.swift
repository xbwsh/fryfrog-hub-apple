import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var auth = AuthService.shared

    enum Tab {
        case home, books, music, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("影视", systemImage: "film.fill")
                }
                .tag(Tab.home)

            BooksTabView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical")
                }
                .tag(Tab.books)

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
