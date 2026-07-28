# Quick Note Colours Design

## Goal

Make Quick Note look like a brighter, classic Post-it by default while letting
the user choose either a curated paper colour or an arbitrary custom colour in
the existing Appearance settings.

## User interface

The existing **Quick Note (Home)** settings group will contain:

- visible colour swatches for Classic Yellow, Pink, Green, Blue, Orange, and
  Purple;
- a native macOS `ColorPicker` labelled **Custom colour**;
- an accessible selected-state label for each swatch.

Selecting a preset clears the custom override. Editing the custom colour
activates the custom override immediately.

## Appearance

Classic Yellow becomes the default paper colour and uses a brighter warm yellow
close to `#FFE56B`. The selected paper colour applies consistently to the
editorial Home post-it and the reusable Quick Note dashboard widget.

Ink colour is derived from paper luminance. Light paper uses dark ink and dark
custom paper uses light ink, preserving readable text, placeholders, icons, and
fold details.

## Persistence and migration

The existing `noteColor` preset remains the authoritative stored preset for
backward compatibility. A new optional Codable custom colour value stores
normalized red, green, blue, and opacity components.

- `nil` custom colour means the selected preset is active;
- a stored custom colour means the custom colour is active;
- existing settings without the new field load unchanged;
- unrelated settings are never reset.

## Testing

Tests will cover:

- brighter Classic Yellow default;
- all curated presets;
- custom colour Codable round-trip;
- preset selection clearing a custom override;
- custom selection overriding the preset;
- automatic light/dark ink contrast;
- legacy settings migration;
- consistent resolution for every Quick Note presentation.

