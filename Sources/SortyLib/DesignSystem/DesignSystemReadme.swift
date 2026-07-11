//
//  DesignSystemReadme.swift
//  Sorty
//
//  Documentation for the Sorty Design System
//

/*
 # Sorty Design System

 ## Overview
 The Sorty Design System provides a centralized, consistent design language for the Sorty macOS app.
 It enables rapid UI development with working SwiftUI previews and ensures visual consistency.

 ## Files

 ### 1. SortyDesignSystem.swift
 Centralized design constants organized into namespaces:

 - **Animation**: Durations, spring configurations, stagger delays, easing curves
   - Animation.quick (0.15s)
   - Animation.standard (0.3s)
   - Animation.springStandard
   - Animation.staggerDelay (0.05s)

 - **Colors**: Brand colors, semantic colors, backgrounds, text colors
   - Colors.primary, Colors.purple, Colors.success
   - Colors.backgroundPrimary, Colors.textSecondary

 - **Typography**: Font sizes, weights, and predefined styles
   - Typography.caption(), Typography.headline(), Typography.title()
   - Typography.mono() for data display

 - **Spacing**: Consistent spacing values
   - Spacing.xs (6), Spacing.md (12), Spacing.xl (20)
   - Spacing.sectionMedium (28)

 - **Sizing**: Icon sizes, button sizes, card sizes, window sizes
   - Sizing.iconMedium (16), Sizing.cardCornerRadius (12)
   - Sizing.windowMinWidth (1000)

 - **Shadows**: Predefined shadow styles
   - Shadows.small, Shadows.medium, Shadows.large

 - **CardStyles**: Reusable card styling
   - CardStyles.standard (ultra-thin material)
   - CardStyles.filled (control background)
   - CardStyles.elevated (with shadow)
   - CardStyles.subtle (minimal)

 ### 2. SortyCard.swift
 Reusable card components:

 - **SortyCard**: General purpose card with optional title and icon
   ```swift
   SortyCard(title: "Settings", icon: "gear", iconColor: .blue) {
       // Content
   }
   ```

 - **SortyNavigationCard**: Card that acts as a navigation button
   ```swift
   SortyNavigationCard(
       title: "Storage",
       description: "Manage storage locations",
       icon: "externaldrive",
       color: .purple
   ) { /* action */ }
   ```

 - **SortyWorkflowCard**: Card for workflow steps
   ```swift
   SortyWorkflowCard(title: "Instructions", icon: "text.bubble") {
       // Content
   }
   ```

 ### 3. PreviewMocks.swift
 Mock data helpers for SwiftUI previews:

 - **PreviewMocks.makeOrganizationPlan()**: Returns a complete mock OrganizationPlan
 - **PreviewMocks.makeFileItems(count:)**: Returns mock FileItem array
 - **PreviewMocks.makeAIConfig()**: Returns mock AIConfig
 - **PreviewMocks.makeStorageLocations()**: Returns mock StorageLocation array
 - **PreviewMocks.makeExclusionRules()**: Returns mock ExclusionRule array

 - **Environment Object Extensions**: Each major class has a `.preview` static property
   - AppState.preview
   - SettingsViewModel.preview
   - FolderOrganizer.preview
   - ExclusionRulesManager.preview
   - And more...

 ## Usage

 ### Using Design System Constants
 ```swift
 Text("Title")
     .font(SortyDesignSystem.Typography.title())
     .foregroundColor(SortyDesignSystem.Colors.textPrimary)
     .padding(SortyDesignSystem.Spacing.lg)
 ```

 ### Using View Extensions
 ```swift
 MyView()
     .sortyCardStyle(.elevated)
     .sortyShadow(.medium)
 ```

 ### Using Transitions
 ```swift
 MyView()
     .transition(.sortyScaleAndFade)
     .transition(.sortySlideFromRight)
 ```

 ### Creating Previews
 ```swift
 #Preview("My View") {
     MyView()
         .environmentObject(SettingsViewModel.preview)
         .environmentObject(FolderOrganizer.preview)
         .frame(width: 900, height: 600)
 }
 ```

 ## Previews Added

 The following views now have comprehensive SwiftUI previews:

 1. **ContentView.swift**: 2 previews (Main, Onboarding)
 2. **OrganizeView.swift**: 4 previews (Idle, Scanning, Ready, Error)
 3. **AnalysisView.swift**: 4 previews (Scanning, Organizing, Applying, Long Running)
 4. **PreviewView.swift**: 2 previews (Standard, With Edits)
 5. **SettingsView.swift**: 5 previews (Rules, Provider, Strategy, Notifications, Advanced)
 6. **OnboardingView.swift**: Multiple step previews

 ## Benefits

 1. **Design-Time Development**: See UI changes instantly in Xcode previews
 2. **Consistency**: Centralized constants ensure visual consistency
 3. **Rapid Iteration**: Mock data allows testing different states without real data
 4. **Documentation**: Previews serve as living documentation of UI states
 5. **Testing**: Easy to verify UI changes across different screen sizes

 ## Best Practices

 1. Use design system constants instead of hardcoded values
 2. Create previews for every significant UI state
 3. Use PreviewMocks for realistic mock data
 4. Add `.preview` static properties to new environment objects
 5. Test previews at different sizes to ensure responsive design

 ## Maintenance

 When adding new views:
 1. Use SortyDesignSystem constants for styling
 2. Add comprehensive previews with different states
 3. Use PreviewMocks for realistic data
 4. Follow existing preview patterns for consistency
 */

import Foundation
