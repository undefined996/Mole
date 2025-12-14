import SwiftUI

struct ContentView: View {
  @State private var appState: AppState = .idle
  @State private var appMode: AppMode = .cleaner  // New Mode State
  @State private var logs: [String] = []
  @State private var showAppList = false
  @State private var showCelebration = false
  @State private var celebrationColors: [Color] = []
  @State private var celebrationMessage: String = ""
  @Namespace private var animationNamespace

  // Connect to Real Logic
  @StateObject private var scanner = ScannerService()
  @StateObject private var uninstaller = UninstallerService()
  @StateObject private var optimizer = OptimizerService()

  // The requested coffee/dark brown color (Cleaner)
  let deepBrown = Color(red: 0.17, green: 0.11, blue: 0.05)  // #2C1C0E

  // Deep Blue for Uninstaller
  let deepBlue = Color(red: 0.05, green: 0.1, blue: 0.2)

  var body: some View {
    ZStack {
      // Dynamic Background
      Color.black.ignoresSafeArea()

      RadialGradient(
        gradient: Gradient(colors: [appMode == .cleaner ? deepBrown : deepBlue, .black]),
        center: .center,
        startRadius: 0,
        endRadius: 600
      )
      .ignoresSafeArea()
      .animation(.easeInOut(duration: 0.5), value: appMode)

      // Custom Top Tab Bar
      VStack {
        HStack(spacing: 0) {
          // Cleaner Tab
          Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
              appMode = .cleaner
            }
          }) {
            Text("Cleaner")
              .font(.system(size: 12, weight: .bold, design: .monospaced))
              .foregroundStyle(appMode == .cleaner ? .black : .white.opacity(0.6))
              .padding(.vertical, 8)
              .padding(.horizontal, 16)
              .background(
                ZStack {
                  if appMode == .cleaner {
                    Capsule()
                      .fill(Color.white)
                      .matchedGeometryEffect(id: "TabHighlight", in: animationNamespace)
                  }
                }
              )
          }
          .buttonStyle(.plain)
          .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
          }

          // Uninstaller Tab
          Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
              appMode = .uninstaller
            }
          }) {
            Text("Uninstaller")
              .font(.system(size: 12, weight: .bold, design: .monospaced))
              .foregroundStyle(appMode == .uninstaller ? .black : .white.opacity(0.6))
              .padding(.vertical, 8)
              .padding(.horizontal, 16)
              .background(
                ZStack {
                  if appMode == .uninstaller {
                    Capsule()
                      .fill(Color.white)
                      .matchedGeometryEffect(id: "TabHighlight", in: animationNamespace)
                  }
                }
              )
          }
          .buttonStyle(.plain)
          .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
          }

          // Optimizer Tab
          Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
              appMode = .optimizer
            }
          }) {
            Text("Optimizer")
              .font(.system(size: 12, weight: .bold, design: .monospaced))
              .foregroundStyle(appMode == .optimizer ? .black : .white.opacity(0.6))
              .padding(.vertical, 8)
              .padding(.horizontal, 16)
              .background(
                ZStack {
                  if appMode == .optimizer {
                    Capsule()
                      .fill(Color.white)
                      .matchedGeometryEffect(id: "TabHighlight", in: animationNamespace)
                  }
                }
              )
          }
          .buttonStyle(.plain)
          .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
          }
        }
        .padding(4)
        .background(
          Capsule()
            .fill(.ultraThinMaterial)
            .opacity(0.3)
        )
        .overlay(
          Capsule()
            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.top, 20)  // Spacing from top

        Spacer()
      }

      VStack(spacing: -10) {
        Spacer()

        // The Mole (Interactive) & Draggable
        // The Mole (Interactive) & Draggable
        MoleView(
          state: $appState,
          appMode: $appMode,
          isRunning: scanner.isScanning || scanner.isCleaning || optimizer.isOptimizing
            || uninstaller.isUninstalling
        )
        .gesture(
          DragGesture()
            .onEnded { value in
              if value.translation.width < -50 {
                withAnimation { appMode = .uninstaller }
              } else if value.translation.width > 50 {
                withAnimation { appMode = .cleaner }
              }
            }
        )
        .onHover { inside in
          if inside {
            NSCursor.pointingHand.set()
          } else {
            NSCursor.arrow.set()
          }
        }
        .opacity(showAppList ? 0.0 : 1.0)  // Hide when list is open
        .animation(.easeInOut, value: showAppList)

        // Status Area
        ZStack {
          // Logs overlay
          if case .scanning = appState, appMode == .cleaner {
            LogView(logs: logs)
              .transition(.opacity)
          } else if case .cleaning = appState, appMode == .cleaner {
            LogView(logs: logs)
              .transition(.opacity)
          } else if appMode == .optimizer && optimizer.isOptimizing {
            LogView(logs: logs)
              .transition(.opacity)
          } else if appMode == .uninstaller && uninstaller.isUninstalling {
            LogView(logs: logs)
              .transition(.opacity)
          } else if showAppList {
            // Showing App List? No status text needed or handled by overlay
            EmptyView()
          } else {
            // Action Button
            Button(action: {
              if appMode == .cleaner {
                if scanner.scanFinished {
                  startCleaning()
                } else {
                  startScanning()
                }
              } else if appMode == .uninstaller {
                handleUninstallerAction()
              } else {
                handleOptimizerAction()
              }
            }) {
              HStack(spacing: 8) {
                if scanner.isScanning || scanner.isCleaning || optimizer.isOptimizing
                  || uninstaller.isUninstalling
                {
                  ProgressView()
                    .controlSize(.small)
                    .tint(.black)
                }

                Text(actionButtonLabel)
                  .font(.system(size: 14, weight: .bold, design: .monospaced))
              }
              .frame(minWidth: 140)
              .padding(.vertical, 12)
              .background(Color.white)
              .foregroundStyle(.black)
              .clipShape(Capsule())
              .shadow(color: .white.opacity(0.2), radius: 10, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .disabled(
              scanner.isScanning || scanner.isCleaning || optimizer.isOptimizing
                || uninstaller.isUninstalling
            )
            .onHover { inside in
              if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
          }
        }
        .frame(height: 100)

        Spacer()
      }

      // App List Overlay
      if showAppList {
        AppListView(
          apps: uninstaller.apps,
          onSelect: { app in
            handleUninstall(app)
          },
          onDismiss: {
            withAnimation { showAppList = false }
          }
        )
        .frame(width: 400, height: 550)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(10)
      }

      if showCelebration {
        VStack(spacing: 8) {
          Spacer()
          ConfettiView(colors: celebrationColors)
            .offset(y: -50)

          VStack(spacing: 4) {
            Text("Success!")
              .font(.system(size: 24, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .shadow(radius: 5)
            if !celebrationMessage.isEmpty {
              Text(celebrationMessage)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 5)
            }
          }
          .offset(y: -150)
        }
        .allowsHitTesting(false)
        .zIndex(100)
        .transition(.scale.combined(with: .opacity))
      }
    }
    .frame(minWidth: 600, minHeight: 500)
    .onChange(of: scanner.currentLog) {
      if !scanner.currentLog.isEmpty {
        withAnimation(.spring) {
          if appMode == .cleaner {
            logs.append(scanner.currentLog)
          }
        }
      }
    }
    .onChange(of: optimizer.currentLog) {
      if !optimizer.currentLog.isEmpty {
        withAnimation(.spring) {
          if appMode == .optimizer {
            logs.append(optimizer.currentLog)
          }
        }
      }
    }
    .onChange(of: uninstaller.currentLog) {
      if !uninstaller.currentLog.isEmpty {
        withAnimation(.spring) {
          if appMode == .uninstaller {
            logs.append(uninstaller.currentLog)
          }
        }
      }
    }
    .onChange(of: appMode) {
      appState = .idle
      logs.removeAll()
      showAppList = false
    }
  }

  // MARK: - Computed Properties

  var actionButtonLabel: String {
    if appMode == .cleaner {
      return scanner.scanFinished ? "Clean" : "Check"
    } else if appMode == .uninstaller {
      return "Scan Apps"
    } else {
      return "Boost"
    }
  }

  // MARK: - Actions

  func startScanning() {
    withAnimation {
      appState = .scanning
      logs.removeAll()
    }

    Task {
      await scanner.startScan()
      let sizeMB = Double(scanner.totalSize) / 1024.0 / 1024.0
      let sizeString =
        sizeMB > 1024 ? String(format: "%.1f GB", sizeMB / 1024) : String(format: "%.0f MB", sizeMB)

      withAnimation {
        appState = .results(size: sizeString)
      }
    }
  }

  func startCleaning() {
    withAnimation {
      appState = .cleaning
      logs.removeAll()
    }

    Task {
      await scanner.cleanSystem()
      withAnimation {
        appState = .done
      }
      triggerCelebration([.orange, .red, .yellow, .white], message: "System Cleaned")
    }
  }

  func handleUninstallerAction() {
    withAnimation { showAppList = true }
    Task { await uninstaller.scanApps() }
  }

  func handleUninstall(_ app: AppItem) {
    withAnimation {
      showAppList = false
      logs.removeAll()
    }

    Task {
      await uninstaller.uninstall(app)
      triggerCelebration(
        [.red, .orange, .yellow, .green, .blue, .purple, .pink, .mint],
        message: "Uninstalled \(app.name)")
    }
  }

  func handleOptimizerAction() {
    Task {
      await optimizer.optimize()
      triggerCelebration([.cyan, .blue, .purple, .mint, .white], message: "Optimized")
    }
  }

  func triggerCelebration(_ colors: [Color], message: String = "") {
    celebrationColors = colors
    celebrationMessage = message
    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showCelebration = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      withAnimation { showCelebration = false }
    }
  }
}
