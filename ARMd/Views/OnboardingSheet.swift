import SwiftUI

struct OnboardingSheet: View {
    let toolchain: Toolchain

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("One thing left to install")
                .font(.title2.weight(.semibold))

            Text("ARMd builds your assembly with Apple's compiler, which isn't set up on this Mac yet. It takes a few minutes and only happens once.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if toolchain.manualStepsNeeded {
                VStack(spacing: 10) {
                    Text("macOS reports the tools are already installed, but they aren't working. Open Software Update and install anything pending, or download the Command Line Tools from Apple.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Download from Apple",
                         destination: URL(string: "https://developer.apple.com/download/all/")!)
                }
            } else if toolchain.isInstalling {
                ProgressView().controlSize(.small)
                Text("Apple's installer is running in its own window. ARMd carries on by itself once it finishes.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Install") { Task { await toolchain.install() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
