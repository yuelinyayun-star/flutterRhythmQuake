// Preserve Dart 3.11 List.sort's ordering of equal rounded-metre distances.
// Adapted from dart-sdk/lib/internal/sort.dart, copyright (c) 2011 the Dart
// project authors, BSD-3-Clause. See THIRD_PARTY_NOTICES.txt.
type Item = (usize, f64);
pub fn sort(a: &mut [Item]) {
    if !a.is_empty() {
        do_sort(a, 0, a.len() as isize - 1);
    }
}
fn cmp(a: Item, b: Item) -> i8 {
    if a.1 < b.1 {
        -1
    } else if a.1 > b.1 {
        1
    } else {
        0
    }
}
fn do_sort(a: &mut [Item], left: isize, right: isize) {
    macro_rules! v {
        ($i:expr) => {
            a[($i) as usize]
        };
    }
    if right - left <= 32 {
        for i in left + 1..=right {
            let el = v!(i);
            let mut j = i;
            while j > left && cmp(v!(j - 1), el) > 0 {
                v!(j) = v!(j - 1);
                j -= 1;
            }
            v!(j) = el;
        }
        return;
    }
    let sixth = (right - left + 1) / 6;
    let index1 = left + sixth;
    let index5 = right - sixth;
    let index3 = (left + right) / 2;
    let index2 = index3 - sixth;
    let index4 = index3 + sixth;
    let mut el1 = v!(index1);
    let mut el2 = v!(index2);
    let mut el3 = v!(index3);
    let mut el4 = v!(index4);
    let mut el5 = v!(index5);
    macro_rules! swap_if {
        ($x:ident,$y:ident) => {
            if cmp($x, $y) > 0 {
                std::mem::swap(&mut $x, &mut $y);
            }
        };
    }
    swap_if!(el1, el2);
    swap_if!(el4, el5);
    swap_if!(el1, el3);
    swap_if!(el2, el3);
    swap_if!(el1, el4);
    swap_if!(el3, el4);
    swap_if!(el2, el5);
    swap_if!(el2, el3);
    swap_if!(el4, el5);
    let pivot1 = el2;
    let pivot2 = el4;
    v!(index1) = el1;
    v!(index3) = el3;
    v!(index5) = el5;
    v!(index2) = v!(left);
    v!(index4) = v!(right);
    let mut less = left + 1;
    let mut great = right - 1;
    let equal = cmp(pivot1, pivot2) == 0;
    let mut k = less;
    if equal {
        while k <= great {
            let ak = v!(k);
            let comp = cmp(ak, pivot1);
            if comp == 0 {
                k += 1;
                continue;
            }
            if comp < 0 {
                if k != less {
                    v!(k) = v!(less);
                    v!(less) = ak;
                }
                less += 1;
            } else {
                loop {
                    let comp = cmp(v!(great), pivot1);
                    if comp > 0 {
                        great -= 1;
                        continue;
                    }
                    if comp < 0 {
                        v!(k) = v!(less);
                        v!(less) = v!(great);
                        less += 1;
                        v!(great) = ak;
                        great -= 1;
                        break;
                    } else {
                        v!(k) = v!(great);
                        v!(great) = ak;
                        great -= 1;
                        break;
                    }
                }
            }
            k += 1;
        }
    } else {
        while k <= great {
            let ak = v!(k);
            if cmp(ak, pivot1) < 0 {
                if k != less {
                    v!(k) = v!(less);
                    v!(less) = ak;
                }
                less += 1;
            } else if cmp(ak, pivot2) > 0 {
                loop {
                    if cmp(v!(great), pivot2) > 0 {
                        great -= 1;
                        if great < k {
                            break;
                        }
                        continue;
                    } else {
                        if cmp(v!(great), pivot1) < 0 {
                            v!(k) = v!(less);
                            v!(less) = v!(great);
                            less += 1;
                            v!(great) = ak;
                            great -= 1;
                        } else {
                            v!(k) = v!(great);
                            v!(great) = ak;
                            great -= 1;
                        }
                        break;
                    }
                }
            }
            k += 1;
        }
    }
    v!(left) = v!(less - 1);
    v!(less - 1) = pivot1;
    v!(right) = v!(great + 1);
    v!(great + 1) = pivot2;
    do_sort(a, left, less - 2);
    do_sort(a, great + 2, right);
    if equal {
        return;
    }
    if less < index1 && great > index5 {
        while cmp(v!(less), pivot1) == 0 {
            less += 1;
        }
        while cmp(v!(great), pivot2) == 0 {
            great -= 1;
        }
        let mut k = less;
        while k <= great {
            let ak = v!(k);
            if cmp(ak, pivot1) == 0 {
                if k != less {
                    v!(k) = v!(less);
                    v!(less) = ak;
                }
                less += 1;
            } else if cmp(ak, pivot2) == 0 {
                loop {
                    if cmp(v!(great), pivot2) == 0 {
                        great -= 1;
                        if great < k {
                            break;
                        }
                        continue;
                    } else {
                        if cmp(v!(great), pivot1) < 0 {
                            v!(k) = v!(less);
                            v!(less) = v!(great);
                            less += 1;
                            v!(great) = ak;
                            great -= 1;
                        } else {
                            v!(k) = v!(great);
                            v!(great) = ak;
                            great -= 1;
                        }
                        break;
                    }
                }
            }
            k += 1;
        }
    }
    do_sort(a, less, great);
}

#[cfg(test)]
mod tests {
    #[test]
    fn repeated_distances_all_sizes_remain_sorted_permutations() {
        for count in 0..1000 {
            let mut a: Vec<_> = (0..count).map(|i| (i, ((i * 193) % 17) as f64)).collect();
            super::sort(&mut a);
            assert!(a.windows(2).all(|p| p[0].1 <= p[1].1));
            let mut ids: Vec<_> = a.iter().map(|p| p.0).collect();
            ids.sort();
            assert_eq!(ids, (0..count).collect::<Vec<_>>());
        }
    }
}
