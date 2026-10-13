KB consulted: A view the platform silently drops looks exactly like a view you forgot to write.
The rendered presentation path must be exercised, including its actual window owner.

# Box image preview presentation

Below 900pt, selecting a Box item presents its detail in a native sheet. An image preview
attached to the browser root competes with that detail sheet for the same presentation
owner. Clicking Open in the detail does not present the large viewer through that sibling
sheet. Above the breakpoint, the inline detail does not occupy the browser's sheet owner.

The image preview is attached to the detail column. In a compact browser, that detail
owns the nested preview sheet; in a wide browser, it presents from the inline pane.
Image opening also selects the requested item so row actions establish the detail owner.

`BoxImagePreviewTests` follows the rendered detail window before clicking Open. Its two
tests retain full-resolution 1800×1200 image checks, error recovery through Retry image,
image aspect ratio and viewport bounds, dismissal, and one-download cache assertions.
The success path exercises 480pt, 800pt and 960pt windows in both appearances and checks
that dismissing the large viewer retains the selected Box item.
