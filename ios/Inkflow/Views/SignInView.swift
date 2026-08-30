import AuthenticationServices
import SwiftUI

/// Account-first entry point. Apple is the primary CTA, Google is a secondary
/// button, and email/password is available via an expandable form. Drives the
/// shared `AuthStore`; once a session exists the app reveals the main flow.
struct SignInView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(AuthStore.self) private var auth

  @State private var showEmail = !BackendConfig.isAppleReady && !BackendConfig.isGoogleReady
  @State private var isCreating = false
  @State private var email = ""
  @State private var password = ""

  private var emailValid: Bool {
    let t = email.trimmingCharacters(in: .whitespaces)
    return t.contains("@") && t.contains(".") && t.count >= 5
  }
  private var formValid: Bool { emailValid && password.count >= 6 }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.paper, Theme.accentSoft.opacity(0.5)],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()

      ScrollView {
        VStack(spacing: Theme.xl) {
          Spacer(minLength: Theme.xxl)
          hero
          Spacer(minLength: Theme.lg)
          authButtons
          if showEmail { emailForm }
          if let error = auth.errorMessage {
            Text(error)
              .font(.footnote)
              .foregroundStyle(.red)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
          legal
          Spacer(minLength: Theme.xl)
        }
        .padding(.horizontal, Theme.xl)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)

      if auth.isWorking {
        Theme.shadow.opacity(0.7).ignoresSafeArea()
        ProgressView().controlSize(.large).tint(Theme.accent)
      }
    }
    .__tenxTrackView("SignInView")
  }

  // Three real covers across three genres (classic, fantasy, mystery),
  // served from the Open Library covers API.
  private let heroCovers: [URL?] = [
    URL(string: "https://covers.openlibrary.org/b/isbn/9780743273565-L.jpg"),  // The Great Gatsby
    URL(string: "https://covers.openlibrary.org/b/isbn/9780547928227-L.jpg"),  // The Hobbit
    URL(string: "https://covers.openlibrary.org/b/isbn/9780307588371-L.jpg"),  // Gone Girl
  ]
  private let coverFallbacks: [UInt] = [0x2E3A59, 0x7A1F3D, 0xC2703D]

  private func coverImage(index i: Int) -> some View {
    AsyncImage(url: heroCovers[i]) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        Color.clear
      }
    }
  }

  private func coverChip(index i: Int) -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color(hex: coverFallbacks[i]))
      .frame(width: 92, height: 134)
      .overlay(coverImage(index: i))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
      .rotationEffect(.degrees(Double(i - 1) * 12))
      .offset(x: CGFloat(i - 1) * 38, y: CGFloat(abs(i - 1)) * 8)
  }

  private var hero: some View {
    VStack(spacing: Theme.md) {
      ZStack {
        ForEach(0..<3, id: \.self) { i in
          coverChip(index: i)
        }
      }
      .frame(height: 160)

      Text("Inkflow")
        .font(.system(.largeTitle, design: .serif).weight(.bold))
        .foregroundStyle(Theme.ink)
      Text("Read or listen to any book. Track your progress across both.")
        .font(.callout)
        .foregroundStyle(Theme.inkSoft)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.sm)
    }
  }

  private var authButtons: some View {
    VStack(spacing: Theme.md) {
      if BackendConfig.isAppleReady {
        SignInWithAppleButton(.continue) { request in
          auth.configureAppleRequest(request)
        } onCompletion: { result in
          auth.handleAppleCompletion(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 54)
        .clipShape(Capsule())
      }

      if BackendConfig.isGoogleReady {
        Button {
          auth.signInWithGoogle()
        } label: {
          HStack(spacing: Theme.sm) {
            Image(systemName: "globe")
              .font(.headline)
            Text("Continue with Google")
              .font(.headline)
          }
          .foregroundStyle(Theme.ink)
          .frame(maxWidth: .infinity)
          .frame(height: 54)
          .background(Theme.surface, in: Capsule())
          .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
      }

      Button {
        withAnimation(.snappy) { showEmail.toggle() }
      } label: {
        Text(showEmail ? "Hide email sign in" : "Continue with email")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.inkSoft)
      }
      .padding(.top, Theme.xs)
    }
  }

  private var emailForm: some View {
    VStack(spacing: Theme.md) {
      TextField("you@example.com", text: $email)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.emailAddress)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .padding(Theme.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline, lineWidth: 1))

      SecureField("Password (6+ characters)", text: $password)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .padding(Theme.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.hairline, lineWidth: 1))

      Button {
        Task {
          if isCreating {
            await auth.signUp(email: email, password: password)
          } else {
            await auth.signIn(email: email, password: password)
          }
        }
      } label: {
        Text(isCreating ? "Create account" : "Sign in")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(formValid ? Theme.accent : Theme.inkFaint, in: Capsule())
      }
      .disabled(!formValid)

      Button {
        withAnimation(.snappy) { isCreating.toggle() }
      } label: {
        Text(isCreating ? "Already have an account? Sign in" : "New here? Create an account")
          .font(.footnote)
          .foregroundStyle(Theme.accent)
      }
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private var legal: some View {
    Text("By continuing you agree to our Terms and Privacy Policy.")
      .font(.caption2)
      .foregroundStyle(Theme.inkFaint)
      .multilineTextAlignment(.center)
  }
}

#Preview {
  SignInView()
    .environment(AuthStore())
}
