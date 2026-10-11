# macOS Box image preview

KB consulted: `macOS Box image preview click full size`. The native-view rendering
record recommends hosted screenshots to verify that the platform mounts the view.
No record identified this specific missing click handler.

## Cause

Box thumbnails downloaded and rendered correctly, but the image view had no action.
The separate Open action handed every media file to the system's default application.
The browser had no in-app image preview destination.

## Behavior

The thumbnail is now a button. Clicking it, or selecting Open for an image, presents
the same native image sheet. Session inspector Box references use that sheet too.
Other file and link opening behavior is preserved.

The sheet reads the authenticated cached original file and decodes it off the main
actor. Its initial view fits the complete image; explicit zoom scrolls larger images.
The native image view accepts the proposed display dimensions instead of forcing its
intrinsic original dimensions into the scroll viewport. Close supports Escape.
Loading failures have an explicit retry action, and Open original uses the local file.

## Verification

A hosted native regression clicks the actual thumbnail, checks the large original
image dimensions and aspect ratio, closes the sheet, and reopens it through Open.
It checks light and dark appearances and verifies that reopening uses one download.
Another hosted regression starts with invalid image bytes, opens the error sheet,
then retries against a healthy media provider and checks the recovered original.
