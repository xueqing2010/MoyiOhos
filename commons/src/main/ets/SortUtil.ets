/**
 * Digit-aware natural ordering so page names sort v2 < v10 (plan D10).
 */
function isDigit(c: string): boolean {
  return c >= '0' && c <= '9';
}

/**
 * Compare two strings naturally: digit runs compare numerically,
 * other characters compare by code point. Returns <0 / 0 / >0.
 */
export function naturalCompare(a: string, b: string): number {
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const ca = a.charAt(i);
    const cb = b.charAt(j);
    if (isDigit(ca) && isDigit(cb)) {
      let ai = i;
      let bj = j;
      while (ai < a.length && isDigit(a.charAt(ai))) {
        ai++;
      }
      while (bj < b.length && isDigit(b.charAt(bj))) {
        bj++;
      }
      const rawA = a.substring(i, ai);
      const rawB = b.substring(j, bj);
      let za = 0;
      while (za < rawA.length - 1 && rawA.charAt(za) === '0') {
        za++;
      }
      let zb = 0;
      while (zb < rawB.length - 1 && rawB.charAt(zb) === '0') {
        zb++;
      }
      const tA = rawA.substring(za);
      const tB = rawB.substring(zb);
      if (tA.length !== tB.length) {
        return tA.length - tB.length;
      }
      if (tA !== tB) {
        return tA < tB ? -1 : 1;
      }
      if (rawA.length !== rawB.length) {
        return rawA.length - rawB.length;
      }
      i = ai;
      j = bj;
    } else {
      const codeA = a.codePointAt(i) ?? 0;
      const codeB = b.codePointAt(j) ?? 0;
      if (codeA !== codeB) {
        return codeA - codeB;
      }
      i++;
      j++;
    }
  }
  const remA = a.length - i;
  const remB = b.length - j;
  if (remA === remB) {
    return 0;
  }
  return remA < remB ? -1 : 1;
}

/** Return a NEW naturally-sorted array (input untouched). */
export function naturalSort(names: Array<string>): Array<string> {
  const copy: Array<string> = names.slice(0, names.length);
  copy.sort((a: string, b: string): number => naturalCompare(a, b));
  return copy;
}
