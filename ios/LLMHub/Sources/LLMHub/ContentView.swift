import SwiftUI

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                onNavigateToChat: { path.append(Screen.chat) },
                onNavigateToModels: { path.append(Screen.models) },
                onNavigateToSettings: { path.append(Screen.settings) },
                onNavigateToRoute: { route in
                    switch route {
                    case "writing_aid":
                        path.append(Screen.writingAid)
                    case "translator":
                        path.append(Screen.translator)
                    case "transcriber":
                        path.append(Screen.transcriber)
                    case "scam_detector":
                        path.append(Screen.scamDetector)
                    case "image_generator":
                        path.append(Screen.imageGenerator)
                    case "vibe_coder":
                        path.append(Screen.vibeCoder)
                    default:
                        break
                    }
                }
            )
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .chat:
                    ChatScreen(
                        onNavigateToSettings: { path.append(Screen.settings) },
                        onNavigateToModels: { path.append(Screen.models) },
                        onNavigateBack: { path.removeLast() }
                    )
                    .navigationBarBackButtonHidden(true)
                case .models:
                    ModelDownloadScreen(onNavigateBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                case .settings:
                    SettingsScreen(
                        onNavigateBack: { path.removeLast() },
                        onNavigateToModels: { path.append(Screen.models) }
                    )
                    .navigationBarBackButtonHidden(true)
                case .writingAid:
                    WritingAidScreen(onNavigateBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                case .translator:
                    TranslatorScreen(
                        onNavigateBack: { path.removeLast() },
                        onNavigateToModels: { path.append(Screen.models) }
                    )
                    .navigationBarBackButtonHidden(true)
                case .transcriber:
                    TranscriberScreen(onNavigateBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                case .scamDetector:
                    ScamDetectorScreen(onNavigateBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                case .vibeCoder:
                    VibeCoderScreen(onNavigateBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                case .imageGenerator:
                    ImageGeneratorScreen(
                        onNavigateBack: { path.removeLast() },
                        onNavigateToModels: { path.append(Screen.models) }
                    )
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
    }
}

enum Screen: Hashable {
    case chat
    case models
    case settings
    case writingAid
    case translator
    case transcriber
    case scamDetector
    case vibeCoder
    case imageGenerator
}
