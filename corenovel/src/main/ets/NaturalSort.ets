/** 自然序比较（第2章 排在 第10章 前）。 */
export function naturalCompare(a: string, b: string): number {
  const left = a.toLowerCase();
  const right = b.toLowerCase();
  let i = 0;
  let j = 0;
  while (i < left.length && j < right.length) {
    const ca = left.charCodeAt(i);
    const cb = right.charCodeAt(j);
    const da = ca >= 48 && ca <= 57;
    const db = cb >= 48 && cb <= 57;
    if (da && db) {
      let na = 0;
      let nb = 0;
      while (i < left.length && left.charCodeAt(i) >= 48 && left.charCodeAt(i) <= 57) {
        na = na * 10 + (left.charCodeAt(i) - 48);
        i++;
      }
      while (j < right.length && right.charCodeAt(j) >= 48 && right.charCodeAt(j) <= 57) {
        nb = nb * 10 + (right.charCodeAt(j) - 48);
        j++;
      }
      if (na !== nb) {
        return na - nb;
      }
      continue;
    }
    if (ca !== cb) {
      return ca - cb;
    }
    i++;
    j++;
  }
  return (left.length - i) - (right.length - j);
}

/** 自然序排序（原地）。 */
export function naturalSortArray(list: Array<string>): Array<string> {
  list.sort((a: string, b: string): number => naturalCompare(a, b));
  return list;
}
