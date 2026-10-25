import { fileUri } from '@kit.CoreFileKit';

/**
 * Media path helpers.
 *
 * ArkUI's Image component does NOT accept a raw sandbox path like
 * /data/storage/el2/base/haps/entry/files/xxx.png — it needs a sandbox URI
 * (file://<bundle>/<sandboxPath>) or a PixelMap. Imported pages, covers and
 * exported previews are stored as sandbox paths, so every Image source and
 * ImageSource creation should pass through toMediaUri().
 */
export function toMediaUri(pathOrUri: string): string {
  if (pathOrUri.length === 0) {
    return pathOrUri;
  }
  if (pathOrUri.startsWith('file://') || pathOrUri.startsWith('http://') ||
    pathOrUri.startsWith('https://') || pathOrUri.startsWith('datashare://') ||
    pathOrUri.startsWith('content://') || pathOrUri.startsWith('ohos://') ||
    pathOrUri.startsWith('$')) {
    return pathOrUri;
  }
  if (pathOrUri.startsWith('/')) {
    try {
      return fileUri.getUriFromPath(pathOrUri);
    } catch (e) {
      return pathOrUri;
    }
  }
  return pathOrUri;
}

/** True when the value is already a URI accepted by Image / ImageSource. */
export function isUri(value: string): boolean {
  return value.startsWith('file://') || value.startsWith('http://') || value.startsWith('https://') ||
    value.startsWith('datashare://') || value.startsWith('content://');
}
