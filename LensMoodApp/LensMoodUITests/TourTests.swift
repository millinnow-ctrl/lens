import XCTest

/// TourTests — the automated interactive click-through the owner asked for:
/// "take screenshots and click on stuff on this app, to see if it's almost
/// complete." Each ordered test launches the real app in the simulator, taps
/// through one product surface, and attaches a numbered, named screenshot at
/// every step. CI exports these attachments so the whole tour can be reviewed
/// as evidence and a completeness verdict written from it.
///
/// Design laws (from the task):
///   • The ONLY hard assertion is that the app launched. Everything else is a
///     soft, tolerant interaction: a missing control is a *finding*, recorded
///     with an XCTContext activity + a screenshot, never an abort. The tour's
///     product is evidence, so it must always reach the end and always leave a
///     picture — a first-run failure degrades to partial evidence, not a red
///     run.
///   • No sleeps beyond what an animation demands; `waitForExistence` with
///     sensible timeouts everywhere.
///   • Each surface is its own ordered test with its own fresh launch, so a
///     wedged system sheet (e.g. the share sheet) in one surface cannot corrupt
///     the surfaces that follow.
///
/// The app is launched with LENSMOOD_DEMO=1 — a bundled demo library, so the
/// Library / Print Room / Capture thumbnail show their populated state with no
/// camera or Photos dependency. The develop-with-a-photo surface (which
/// otherwise needs the system PhotosPicker a UI test cannot drive) is reached
/// through the app's existing inert LENSMOOD_AD screenshot harness instead.
final class TourTests: XCTestCase {

  /// global step counter so the whole tour numbers 01…NN in tap order across
  /// every ordered test (the methods run sequentially in one simulator)
  private static var step = 0

  override func setUpWithError() throws {
    // soft-continue: a recorded miss must not stop the remaining taps
    continueAfterFailure = true
  }

  // MARK: - Launch

  /// a fresh app process; `extra` is merged over the demo defaults
  @discardableResult
  private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
    let app = XCUIApplication()
    var env = ["LENSMOOD_DEMO": "1"]
    for (key, value) in extra { env[key] = value }
    app.launchEnvironment = env
    app.launch()
    return app
  }

  // MARK: - Evidence helpers

  /// capture the whole screen (so system alerts / share sheets are included)
  /// as a keep-always, numbered, named attachment
  private func shot(_ name: String) {
    Self.step += 1
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = String(format: "%02d-%@", Self.step, name)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// record that an expected control was absent — a *finding*, not a failure:
  /// name what was expected in the test report and leave a screenshot of how
  /// far the tour got
  private func miss(_ expected: String, _ name: String) {
    XCTContext.runActivity(named: "MISS — expected: \(expected)") { _ in
      shot("miss-\(name)")
    }
  }

  /// tap a control if it appears and is hittable within `timeout`; otherwise
  /// record a miss and carry on. Returns whether the tap happened.
  @discardableResult
  private func tap(_ element: XCUIElement, _ expected: String,
                   name: String, timeout: TimeInterval = 6) -> Bool {
    if element.waitForExistence(timeout: timeout), element.isHittable {
      element.tap()
      return true
    }
    miss(expected, name)
    return false
  }

  /// the default back button of the top navigation bar (the leading chevron)
  private func back(_ app: XCUIApplication) {
    let button = app.navigationBars.buttons.firstMatch
    if button.waitForExistence(timeout: 4), button.isHittable { button.tap() }
  }

  // MARK: - 01 · Cameras home + the develop surface (via a camera card)

  func test01_camerasHomeAndDevelopSurface() {
    let app = launch()

    // THE ONE HARD ASSERTION: the app came up. Everything downstream is soft.
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    shot("cameras-home")

    // scroll the signature camera carousel sideways — a deterministic
    // horizontal drag across the strip that sits just under the hero
    let carouselStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.42))
    let carouselEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.42))
    carouselStart.press(forDuration: 0.05, thenDragTo: carouselEnd)
    shot("cameras-carousel-scrolled")

    // scroll the page down to the camera grid, then open Street 35's develop
    app.swipeUp()
    let streetCard = app.buttons["camera-card-leica-street"]
    if !tap(streetCard, "Street 35 camera card in the grid", name: "street-card") {
      // the grid may sit further down — one more scroll, then retry
      app.swipeUp()
      tap(streetCard, "Street 35 camera card in the grid", name: "street-card-2")
    }

    // the develop surface for a camera opened without a photo yet: camera
    // identity, the style rail, the (disabled) preview control, and the photo
    // chooser prompt. Reached with no system picker involved.
    if app.navigationBars["Street 35"].waitForExistence(timeout: 8) {
      shot("develop-surface-street35")
    } else {
      miss("develop surface titled 'Street 35'", "develop-surface")
    }

    // the style rail switches the loaded camera in place — tap two more
    // cameras; the nav title (currentStock.name) is the visible proof
    tap(app.buttons["Develop with Noir"], "style-rail chip: Noir", name: "rail-noir")
    if app.navigationBars["Noir"].waitForExistence(timeout: 5) { shot("develop-rail-noir") }
    tap(app.buttons["Develop with Neon Night"], "style-rail chip: Neon Night", name: "rail-neon")
    if app.navigationBars["Neon Night"].waitForExistence(timeout: 5) { shot("develop-rail-neon") }

    // without a photograph the Original/Developed/Compare control is disabled —
    // capture that honest state (the segmented preview needs a developed image,
    // supplied in test02)
    shot("develop-preview-disabled")

    back(app)
    // HomeView carries no navigation title, so its stable "we're home" signal
    // is the account toolbar button rather than a titled nav bar
    _ = app.buttons["Account and privacy"].waitForExistence(timeout: 5)
    shot("back-to-cameras-home")
  }

  // MARK: - 02 · Develop flow with a real developed photograph (AD harness)

  func test02_developWithPhoto() {
    // LENSMOOD_AD boots straight into a develop that runs the engine on a
    // bundled photograph — the one path to a *developed* stage without the
    // system PhotosPicker. The style rail + preview toggle then have real
    // pixels to act on.
    let app = launch(["LENSMOOD_AD": "1", "LENSMOOD_AD_STOCK": "leica-street"])
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    // wait for the develop to actually land: the look-strength slider only
    // renders once a developed image exists (the preview segments render even
    // while still disabled mid-develop, so they are not a reliable gate). The
    // engine pipeline can take several seconds.
    let strength = app.sliders["Look strength"]
    let ready = strength.waitForExistence(timeout: 25)
    if !ready { miss("developed stage (look-strength slider) after engine run", "develop-not-ready") }
    shot("develop-developed-street35")

    // toggle the preview modes and screenshot each genuine state
    if tap(app.buttons["Original"], "preview segment: Original", name: "seg-original") {
      shot("develop-preview-original")
    }
    if tap(app.buttons["Compare"], "preview segment: Compare", name: "seg-compare") {
      shot("develop-preview-compare")
    }
    if tap(app.buttons["Developed"], "preview segment: Developed", name: "seg-developed") {
      shot("develop-preview-developed")
    }

    // pull the look-strength slider back — the developed preview restyles live
    if strength.waitForExistence(timeout: 4) {
      strength.adjust(toNormalizedSliderPosition: 0.35)
      shot("develop-strength-35pct")
    } else {
      miss("look-strength slider", "strength")
    }

    // switch cameras on the rail — each re-develops the same photograph
    if tap(app.buttons["Develop with Noir"], "style-rail chip: Noir", name: "rail-noir-photo") {
      _ = app.navigationBars["Noir"].waitForExistence(timeout: 6)
      shot("develop-switch-noir")
    }
    if tap(app.buttons["Develop with Neon Night"], "style-rail chip: Neon Night",
           name: "rail-neon-photo") {
      _ = app.navigationBars["Neon Night"].waitForExistence(timeout: 6)
      shot("develop-switch-neon")
    }
  }

  // MARK: - 03 · Library: a roll, a frame, favorite, share, print hand-off

  func test03_library() {
    let app = launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    tap(app.buttons["Library"], "Library dock tab", name: "library-tab")
    _ = app.navigationBars["Library"].waitForExistence(timeout: 6)
    shot("library-rolls")

    // open the first mounted frame (its label reads "<camera>, exposure <n>")
    let frame = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@", ", exposure")
    ).firstMatch
    if tap(frame, "a developed frame in the roll", name: "frame-cell") {
      _ = app.navigationBars["Frame"].waitForExistence(timeout: 6)
      shot("library-frame-detail")
    }

    // favorite it (toolbar heart) — the glyph flips to filled
    let fav = app.buttons["Add favorite"]
    if tap(fav, "Add-favorite toolbar button", name: "favorite") {
      shot("library-frame-favorited")
    } else if app.buttons["Remove favorite"].exists {
      // already a seeded favorite — toggle it to prove the control is live
      app.buttons["Remove favorite"].tap()
      shot("library-frame-favorite-toggled")
    }

    // the share affordance opens the system share sheet — screenshot it, then
    // dismiss defensively (a wedge here cannot reach later surfaces: they are
    // separate tests)
    if tap(app.buttons["Share"], "Share button", name: "share") {
      shot("library-share-sheet")
      dismissSystemSheet(app)
    }

    // the frame detail is the menu of onward actions — capture the full set
    // (Shoot this film again / Save / Share / Share as camera card / Print /
    // Delete) as evidence they exist
    _ = app.buttons["Print this frame"].waitForExistence(timeout: 4)
    shot("library-frame-actions")

    // "Print this frame" carries the kept frame to the Print Room (dismisses
    // the sheet and switches tab)
    if tap(app.buttons["Print this frame"], "Print this frame button", name: "print-frame") {
      _ = app.navigationBars["Print"].waitForExistence(timeout: 6)
      shot("library-print-handoff")
    }
  }

  // MARK: - 04 · Print Room: populated state + surface switches

  func test04_printRoom() {
    let app = launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    tap(app.buttons["Print"], "Print dock tab", name: "print-tab")
    _ = app.navigationBars["Print"].waitForExistence(timeout: 6)
    // the print develops in with a ~2.2s emulsion clear — let it settle
    _ = app.staticTexts["A photograph becomes an object."].waitForExistence(timeout: 4)
    shot("print-populated")

    // the surface picker restyles the printed object under the frame; the Save
    // button is deliberately NOT tapped (it writes to Photos → a system
    // permission dialog the tour must not trip)
    for surface in ["Linen", "Marble", "Concrete"] {
      if tap(app.buttons[surface], "print surface: \(surface)", name: "surface-\(surface.lowercased())") {
        shot("print-surface-\(surface.lowercased())")
      }
    }
  }

  // MARK: - 05 · Tape (camcorder): idle deck + record affordance

  func test05_tape() {
    let app = launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    tap(app.buttons["Tape"], "Tape dock tab", name: "tape-tab")
    _ = app.navigationBars["Tape"].waitForExistence(timeout: 6)
    shot("tape-idle-deck")

    // "Record a tape" — the simulator has no camera, so the app's own
    // "Camera unavailable" alert appears (an in-fiction, in-app dialog, not a
    // system permission prompt). "Load an existing clip" is skipped because it
    // opens the system videos picker the tour cannot drive.
    if tap(app.buttons["Record a tape"], "Record a tape button", name: "record") {
      let alert = app.alerts["Camera unavailable"]
      if alert.waitForExistence(timeout: 4) {
        shot("tape-camera-unavailable")
        alert.buttons["OK"].tap()
      } else {
        miss("'Camera unavailable' alert on the simulator", "record-alert")
      }
    }
    shot("tape-after-record")
  }

  // MARK: - 06 · Capture: viewfinder fallback + pure-UI dials and mount

  func test06_capture() {
    // LENSMOOD_TAB=capture lands directly on the camera and suppresses the
    // first-run guide (the app treats a scripted launch as non-first-run), so
    // the viewfinder fallback state is captured deterministically
    let app = launch(["LENSMOOD_TAB": "capture"])
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    // the Simulator has no camera feed — this is the instrument's fallback UI
    _ = app.buttons["Shutter"].waitForExistence(timeout: 6)
    shot("capture-viewfinder")

    // mode switch (Portrait, not Video — Video routes to the camcorder)
    if tap(app.buttons["Portrait"], "capture mode: Portrait", name: "mode-portrait") {
      shot("capture-mode-portrait")
    }
    // the scene-relight dial
    if tap(app.buttons["Auto light"], "Auto-light dial", name: "autolight") {
      shot("capture-autolight-toggled")
    }
    // a zoom stop (pure UI: applies a zoom factor, no capture)
    if tap(app.buttons["2× zoom"], "2× zoom dial", name: "zoom") {
      shot("capture-zoom-2x")
    }
    // composition grid overlay
    if tap(app.buttons["Composition grid"], "composition-grid toggle", name: "grid") {
      shot("capture-grid-on")
    }

    // the film-mount picker (in-app sheet, not a system picker): open, capture
    // the shelf, then load Street 35 (which closes the sheet)
    if tap(app.buttons["capture-film-picker"], "film-mount picker button", name: "mount-open") {
      if app.navigationBars["Load a film"].waitForExistence(timeout: 5) {
        shot("capture-mount-picker")
        if !tap(app.buttons["Load Street 35"], "mount cell: Load Street 35",
                name: "mount-load") {
          app.swipeDown()   // fallback dismissal if the cell drifted
        }
        shot("capture-mount-loaded")
      } else {
        miss("'Load a film' mount sheet", "mount-sheet")
      }
    }

    // leave the camera the way a user does — the in-viewfinder back control
    if tap(app.buttons["Back to LensMood"], "Back-to-LensMood control", name: "capture-back") {
      _ = app.buttons["Account and privacy"].waitForExistence(timeout: 5)
      shot("capture-back-to-cameras")
    }
  }

  // MARK: - 07 · Account sheet (reachable from the cameras home)

  func test07_account() {
    let app = launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                  "The app must reach the foreground.")

    if tap(app.buttons["Account and privacy"], "Account toolbar button", name: "account-open") {
      if app.navigationBars["Account"].waitForExistence(timeout: 6) {
        // membership (Everything free for now), the on-device privacy line,
        // and the version row — the paywall is NOT expected (gates are off)
        shot("account-sheet")
        tap(app.buttons["Done"], "Account Done button", name: "account-done")
      } else {
        miss("Account sheet", "account-sheet")
      }
    }
    shot("account-dismissed")
  }

  // MARK: - System-sheet dismissal

  /// dismiss a presented system sheet (the share sheet) as robustly as the
  /// simulator allows: a Close/Cancel button if the OS offers one, otherwise a
  /// swipe-down on the sheet
  private func dismissSystemSheet(_ app: XCUIApplication) {
    for label in ["Close", "Cancel"] {
      let button = app.buttons[label]
      if button.exists, button.isHittable { button.tap(); return }
    }
    app.swipeDown()
    // if a stray sheet lingers, a tap near the top dims-area helps it close
    if app.buttons["Print this frame"].waitForExistence(timeout: 3) == false {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
    }
  }
}
