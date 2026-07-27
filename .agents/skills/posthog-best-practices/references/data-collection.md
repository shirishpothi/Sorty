# Controlling data collection - Docs

PostHog offers a range of controls to help you manage data collection. This guide covers data collection controls available to you **before** data reaches PostHog servers.

You should consider the following tools to help you manage data collection:

| Feature | Description |
| --- | --- |
| [Asking for opt out](#asking-for-opt-out) | A top-level opt out of all data collection |
| [Using a consent management platform](#using-posthog-with-a-consent-management-platform-cmp) | Integrate PostHog with a CMP like OneTrust or Cookiebot |
| [IP data capture](#ip-data-capture) | Control whether client IP addresses are captured or discarded |
| [Autocapture behavior](#autocapture) | Configure what elements and interactions are automatically captured |
| [Masking sensitive information](#masking-sensitive-information) | Prevent specific sensitive data from being collected |
| [Overriding captured events](#overriding-captured-events) | Modify or filter event data before it's sent to PostHog |
| [Cookieless tracking](#cookieless-tracking) | Track users without using browser cookies |
| [Identifying users](#identifying-users) | Set up user identification and manage user properties |

If you require that certain data never reaches PostHog servers, you can use one of the tools below to prevent data from being captured.

## Asking for opt out

Before capturing data, you may need to ask your users for consent. PostHog provides a top level switch to control data collection.

Opting out on a PostHog client will prevent **all data** from being captured and sent to PostHog. This includes any autocaptures, manual captures, and session replays.

### Opting in and out

You can opt out the current device by calling `posthog.opt_out_capturing()`.

PostHog AI

### Web

```javascript
posthog.opt_out_capturing()
```

### iOS

```swift
PostHogSDK.shared.optOut()
```

### Android

```java
PostHog.optOut()
```

### React Native

```jsx
posthog.optOut()
```

Similarly, you can opt users in:

PostHog AI

### Web

```javascript
posthog.opt_in_capturing()
```

### iOS

```swift
PostHogSDK.shared.optIn()
```

### Android

```java
PostHog.optIn()
```

### React Native

```jsx
posthog.optIn()
```

### Checking if a user is opted out

You can check if a user is opted out by calling `posthog.has_opted_out_capturing()`.

PostHog AI

### Web

```javascript
posthog.has_opted_out_capturing()
```

### iOS

```swift
PostHogSDK.shared.isOptOut()
```

### Android

```java
PostHog.isOptOut()
```

### React Native

```jsx
posthog.optedOut
```

### Opt out preference persistence

Opting out status is persisted automatically using:

-   **local storage** or **cookies** for browsers
-   **shared preferences** for Android
-   **`posthog.optOut`** file in your app's support directory for iOS
-   **`.posthog-rn.json`** for React Native

For browsers, you can control how long the opt out state is persisted by setting `opt_out_capturing_persistence_type` to either `local_storage` or `cookies`.

Web

PostHog AI

```javascript
posthog.init('<ph_project_token>', {
    opt_out_capturing_persistence_type: 'local_storage',
});
```

To persist opt out across sessions and devices, you can save your user's opt out preferences in your app logic. On launch, you can check if the user has opted out and set the opt out state accordingly.

### Opting out by default

To opt users out by default, set `opt_out_capturing_by_default` to `true` in the `init` call.

PostHog AI

### Web

```javascript
posthog.init('<ph_project_token>', {
    opt_out_capturing_by_default: true,
});
```

### iOS

```swift
let config = PostHogConfig(projectToken: "<ph_project_token>", host: "https://us.i.posthog.com")
config.optOut = true
PostHogSDK.shared.setup(config)
```

### Android

```java
val config = PostHogAndroidConfig(
    apiKey = <ph_project_token>,
    host = https://us.i.posthog.com
)
config.optOut = true
PostHogAndroid.setup(this, config)
```

### React Native

```jsx
<PostHogProvider
    apiKey="<ph_project_token>"
    options={{
        host: 'https://us.i.posthog.com',
        defaultOptIn: false,
    }}
>
    ...
</PostHogProvider>
```

### Using PostHog with a consent management platform (CMP)

If you use a consent management platform (such as OneTrust, Cookiebot, Osano, Usercentrics, or a home-grown banner), integrate it with PostHog's opt in and out controls rather than the loader snippet.

**Don't gate the snippet behind consent**

A common mistake is wrapping the PostHog snippet (or `<script>` tag) so that it only runs after consent is given. Many CMPs make this easy by letting you tag scripts as a specific cookie category and blocking them until the user accepts.

The problem: if the SDK never loads, it can't count the visitors who ignore or dismiss the banner, and it can't respect a consent choice made later in the session. This is a frequent cause of sudden, large drops in event volume.

**Always load posthog-js.** Control whether it captures data using the opt in and out APIs below.

The recommended pattern is to load PostHog opted out by default, then opt the user in once they consent:

1.  Initialize PostHog with `opt_out_capturing_by_default: true` (see [opting out by default](#opting-out-by-default)) so nothing is captured until the user consents.
2.  When the user grants consent, call `posthog.opt_in_capturing()`.
3.  When the user withdraws or denies consent, call `posthog.opt_out_capturing()`.

Web

PostHog AI

```javascript
posthog.init('<ph_project_token>', {
    api_host: 'https://us.i.posthog.com',
    defaults: '2026-05-30',
    opt_out_capturing_by_default: true,
})
// Wire these into your CMP's consent-change callback
function onConsentChange(hasConsented) {
    if (hasConsented) {
        posthog.opt_in_capturing()
    } else {
        posthog.opt_out_capturing()
    }
}
```

Every CMP (OneTrust, Cookiebot, and others) exposes some kind of callback or event that fires when consent changes. Call `opt_in_capturing()` and `opt_out_capturing()` from that callback, using whatever consent-change hook your CMP provides.

Alternatively, use [cookieless tracking](#cookieless-tracking) with `cookieless_mode: "on_reject"`. PostHog still loads and counts users with a privacy-preserving hash, and only starts storing cookies once the user opts in – without you needing to wire up the opt in and out calls yourself.

## IP data capture

You can control whether client IP addresses are captured or discarded at both the organization and project levels. This helps ensure consistent privacy controls across all environments.

### Organization-level configuration

Organizations can set a default IP data capture policy that automatically applies to all new projects created within the organization. This eliminates the need to manually configure IP data capture settings for each new environment.

To configure the organization default:

1.  Go to **Settings** > **Organization** > **General**
2.  Find the **IP data capture default** setting
3.  Choose whether new projects should capture or discard client IP data by default

**EU organizations**: Automatically default to IP data capture disabled for GDPR compliance. This ensures that all new projects created in EU organizations are configured with appropriate privacy settings from the start.

### Project-level configuration

Individual projects can configure their own IP data capture setting, which overrides the organization default if needed. This is useful when you have specific privacy requirements for a particular project or environment.

To configure at the project level:

1.  Go to **Settings** > **Project** > **General**
2.  Find the **IP data capture configuration** setting
3.  Choose whether this project should capture or discard client IP data

### How it works

-   **New projects**: Automatically inherit the organization's IP data capture default setting
-   **Existing projects**: Are not affected by organization-level changes - they retain their current configuration
-   **Project-level override**: Individual projects can override the organization default if needed
-   **Privacy compliance**: Disabling IP capture helps with GDPR and other privacy regulations by preventing collection of identifiable network information

## Autocapture

PostHog has powerful autocapture features that capture data automatically on the client side. Autocapture is available for Web, iOS, and React Native, and is used by **product analytics**, **web vitals**, and **heatmaps**.

### Project level autocapture controls

You can control autocapture behavior at the project level in **Settings** > **Project** > [**Autocapture & heatmaps**](https://us.posthog.com/settings/project-autocapture).

### Session level autocapture controls

You can also control autocapture behavior programmatically on the client side.

## Web

In web apps using the [JavaScript Web SDK](/docs/libraries/js.md), the following data can be autocaptured.

| Feature | Data captured |
| --- | --- |
| Product analytics | Pageviews, pageleaves, clicks, changes of inputs, and form submissions associated with <a>, <button>, <form>, <input>, <select>, <textarea>, and <label> tags |
| Web analytics | Pageviews, pageleaves, conversions, and [web vitals](https://github.com/GoogleChrome/web-vitals) |
| Session replay | Clicks, mouse movements, scrolling, and snapshots of the DOM |
| Error tracking | Exceptions thrown in the browser using onError and onUnhandledRejection |

You can control autocapture using the `autocapture` option in the `posthog.init` call.

You can disable autocapture entirely by setting `autocapture` to `false`.

Web

PostHog AI

```javascript
posthog.init('<ph_project_token>', {
    api_host: 'https://us.i.posthog.com',
    autocapture: false,
})
```

You can also control what is captured using the `AutocaptureConfig` object.

Web

PostHog AI

```javascript
posthog.init('<ph_project_token>', {
    api_host: 'https://us.i.posthog.com',
    autocapture: {
        dom_event_allowlist: ['click'], // DOM events from this list ['click', 'change', 'submit']
        url_allowlist: ['posthog.com./docs/.*'], // strings or RegExps
        // url_ignorelist can be used on its own, or combined with url_allowlist to further filter which URLs are captured
        url_ignorelist: ['posthog.com./docs/.*/secret-section/.*'], // strings or RegExps
        element_allowlist: ['button'], // DOM elements from this list ['a', 'button', 'form', 'input', 'select', 'textarea', 'label']
        css_selector_allowlist: ['[ph-autocapture]'], // List of CSS selectors to capture
        // List of CSS selectors to ignore. Providing a custom list replaces the defaults,
        // so include .ph-no-autocapture and [data-ph-no-autocapture] if you still want them ignored.
        css_selector_ignorelist: ['.ph-no-autocapture', '[data-ph-no-autocapture]', '[data-sensitive]'],
        element_attribute_ignorelist:['data-attr-pii="email"'], // List of element attributes to ignore
    },
})
```

## iOS

In iOS apps using the PostHog [iOS SDK](/docs/libraries/ios.md), the following data can be autocaptured.

-   **Application Opened**: when the app is opened from a closed state or when the app comes to the foreground (e.g. from the app switcher)
-   **Application Backgrounded**: when the app is sent to the background by the user
-   **Application Installed**: when the app is installed
-   **Application Updated**: when the app is updated
-   **$screen**: when the user navigates if using `UIViewController`
-   **$rageclick**: when the user rapidly taps in the same area if using `UIKit`
-   **$autocapture**: when the user interacts with elements in a screen if using `UIKit` and `captureElementInteractions` is enabled

This autocapture behavior can be further controlled using the `PostHogConfig` object.

AppDelegate.swift

PostHog AI

```swift
config.captureScreenViews = true
// capture application lifecycle events (installed, updated, opened, backgrounded)
config.captureApplicationLifecycleEvents = true
// capture element interactions (button presses, text input changes, etc.)
config.captureElementInteractions = true
PostHogSDK.shared.setup(config)
```

## React Native

In web apps using the PostHog [React Native SDK](/docs/libraries/react-native.md), the following data can be autocaptured.

-   **Application Opened** - when the app is opened from a closed state
-   **Application Became Active** - when the app comes to the foreground (e.g. from the app switcher)
-   **Application Backgrounded** - when the app is sent to the background by the user
-   **Application Installed** - when the app is installed.
-   **Application Updated** - when the app is updated.
-   **$screen** - when the user navigates (if using `@react-navigation/native` (v6 or lower) or `react-native-navigation`), check out the [capturing screen views](/docs/libraries/react-native.md#capturing-screen-views) section
-   **$autocapture** - touch events when the user interacts with the screen
-   **$exception** - when the app throws exceptions.

React Native

PostHog AI

```jsx
<PostHogProvider apiKey="<ph_project_token>" autocapture={{
    captureTouches: true, // Disabled by default
    captureScreens: true, // Enabled by default
    ignoreLabels: [], // Any labels here will be ignored from the stack in touch events
    customLabelProp: "ph-label",
    maxElementsCaptured: 20,
    noCaptureProp: "ph-no-capture",
    propsToCapture: ["testID"], // Limit which props are captured. By default, identifiers and text content are captured.
    navigation: {
        // By default, only the screen name is tracked but it is possible to track the
        // params or modify the name by intercepting the autocapture like so
        routeToName: (name, params) => {
            if (params.id) return `${name}/${params.id}`
            return name
        },
        routeToProperties: (name, params) => {
            if (name === "SensitiveScreen") return undefined
            return params
        },
    },
}}>
    ...
</PostHogProvider>
```

### Hide sensitive information with autocapture

You can also mask individual elements of the view hierarchy from being captured.

PostHog will make a best effort to not capture sensitive information by default. This is not always sufficient, so you can disable autocapture for specific elements.

## Web

By default, PostHog only collects the `name`, `id`, and `class` attributes from `<input>` tags.

If there are other HTML elements you don't want captured, you can add the `ph-no-capture` class to the element.

Web

PostHog AI

```javascript
<button class='ph-no-capture'>Sensitive information here</button>
```

## iOS

By default, the iOS SDK will make a best effort to avoid capturing password, credit card, OTP, and any other fields related to Personally Identifiable Information (PII).

If there are other elements of the view hierarchy that you don't want to be captured, you can add an `accessibilityLabel` or `accessibilityIdentifier` of `ph-no-capture`

Swift

PostHog AI

```swift
// This view will be excluded from autocapture
let view = UIView()
view.accessibilityLabel = "ph-no-capture"
```

These elements will be ignored or masked in product analytics.

## React Native

If there are elements you don't want to be captured, you can add the `ph-no-capture` property. If this property is found anywhere in the view hierarchy, the entire touch event is ignored:

React Native

PostHog AI

```jsx
<View ph-no-capture>Sensitive view here</View>
```

## Masking sensitive information

You can safely capture [session replays](/docs/session-replay.md) events without compromising your users' privacy. PostHog offers a range of masking techniques that let you mask over sensitive information.

The following masking techniques are available:

-   [Masking inputs](/docs/session-replay/privacy.md#input-elements): Mask out sensitive inputs from being captured. Individual inputs can be unmasked.
-   [Masking text elements](/docs/session-replay/privacy.md#text-elements): Mask out sensitive text from being captured. Individual text elements can be unmasked.
-   [Masking other elements](/docs/session-replay/privacy.md#other-elements): Mask out any individual element from being captured.
-   [Redacting information on network captures](/docs/session-replay/network-recording.md#sensitive-information): Redact sensitive information from network captures.

### Private by default

If you have data that should never be captured, a safe way to start with PostHog is to mask all inputs and text, only selectively unmasking elements that you need to capture.

You can set specific [data attributes](https://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes) on elements to control whether they are captured or not:

Web

PostHog AI

```javascript
{
    // mask all inputs by default
    maskAllInputs: true,
    maskTextSelector: "*",
    maskTextFn: (text, element) => {
        // only elements with `data-capture="true"` will be captured
        if (element?.dataset['capture'] === 'true') {
            return text
        }
        return '*'.repeat(text.trim().length)
    },
}
```

**Mobile session replay masking**

Selectively unmasking elements is not currently available for mobile session replay. You should be more selective about which screens you capture, and take care to mask out sensitive information.

Masking all inputs and text by default in session replay ensures that data is only captured when explicitly unmasked, putting you in control of what's captured.

## Overriding captured events

Before an event is sent to PostHog, you have a final chance to modify it to remove sensitive information. You can do this by using the `before_send` hook. This hook is **only available for the JavaScript Web SDK**.

Web

PostHog AI

```javascript
posthog.init('<ph_project_token>', {
  api_host: 'https://us.i.posthog.com',
  defaults: '2026-05-30',
  before_send: function(event) {
        if (event.properties['$current_url']) {
            event.properties['$current_url'] = null;
        }
        return event;
    },
})
```

## Cookieless tracking

PostHog can be configured to do cookieless tracking by setting `cookieless_mode` to `always` or `on_reject`.

**Cookieless server hash mode**

Before configuring cookieless tracking, you need to enable "Cookieless server hash mode" in your PostHog project settings under **Project Settings** > **Web analytics**.

First is `cookieless_mode: "always"`:

-   Doesn't require a cookie banner (unless something else on your website uses cookies)
-   Never stores PostHog data in cookies or local/session storage
-   Prevents you from calling `identify()`, as a distinct ID would be considered Personal Data under GDPR and other similar privacy regulations
-   Counts the number of users on your site using a privacy-preserving hash, calculated on PostHog's servers

Second is `cookieless_mode: "on_reject"`:

-   Is useful if you do want to show a cookie banner and only enable cookies when the user consents with `posthog.opt_in_capturing()` or similar method
-   Never stores PostHog data in cookies or local/session storage until the user opts in
-   **No events are captured** until after consent is either given or denied
-   If consent is denied, still counts those users, using a privacy-preserving hash calculated on PostHog's servers

**More to do**

Using `cookieless_mode` helps comply with cookie and consent requirements. You still need to configure data collection and [storage](/docs/privacy/data-storage.md) separately to comply with relevant regulations.

Do not send data that could be used to identify users (e.g. setting an email address as a [person property](/docs/product-analytics/person-properties.md) if they have not given consent.

For more information on how to set up cookieless audience measurement, you can follow our detailed tutorial on [cookieless tracking](/docs/tutorials/cookieless-tracking.md).

## Identifying users

To track users across sessions and devices, PostHog needs to identify them. This is done by calling `posthog.identify()`.

Some features depend on [cohorts](/docs/data/cohorts.md) to work well. Some information beyond a basic `distinct_id` is required to use these features:

-   [Feature flags](/docs/feature-flags.md) - target specific user segments in experiments
-   [Surveys](/docs/surveys.md) - Enable for specific cohorts of users
-   [Insights](/docs/product-analytics/insights.md) - filter and breakdown by user characteristics

PostHog AI

### Web

```javascript
posthog.identify(
  'distinct_id',  // Replace 'distinct_id' with your user's unique identifier
  { email: 'max@hedgehogmail.com', name: 'Max Hedgehog' } // optional: set additional person properties
);
```

### Android

```kotlin
PostHog.identify(
    distinctId = distinctID, // Replace 'distinctID' with your user's unique identifier
    // optional: set additional person properties
    userProperties = mapOf(
        "name" to "Max Hedgehog",
        "email" to "max@hedgehogmail.com"
    )
)
```

### iOS

```swift
PostHogSDK.shared.identify("distinct_id", // Replace "distinct_id" with your user's unique identifier
                           userProperties: ["name": "Max Hedgehog", "email": "max@hedgehogmail.com"]) // optional: set additional person properties
```

### React Native

```jsx
posthog.identify('distinct_id', { // Replace "distinct_id" with your user's unique identifier
    email: 'max@hedgehogmail.com', // optional: set additional person properties
    name: 'Max Hedgehog'
})
```

### Dart

```dart
await Posthog().identify(
  userId: 'distinct_id', // Replace "distinct_id" with your user's unique identifier
  userProperties: {
    'email': 'max@hedgehogmail.com', // optional: set additional person properties
    'name': 'Max Hedgehog',
  },
);
```

Information you pass to `posthog.identify()` will be sent to PostHog servers. Depending on your compliance requirements, you may not be able to store some of this information.

If you plan to use these features, consider how you can identify these groups of users without breaking compliance requirements.

### Community questions

Ask a question

### Was this page useful?

HelpfulCould be better