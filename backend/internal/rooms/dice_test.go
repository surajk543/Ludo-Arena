package rooms

import "testing"

// CryptoDice must be unbiased: a naive `byte % 6` would favour 1..4 by
// 43/42, which this chi-square test detects at this sample size.
func TestCryptoDiceIsUniform(t *testing.T) {
	const rolls = 600_000
	var counts [7]int
	d := CryptoDice{}
	for range rolls {
		v := d.Roll()
		if v < 1 || v > 6 {
			t.Fatalf("roll out of range: %d", v)
		}
		counts[v]++
	}
	expected := float64(rolls) / 6
	chi2 := 0.0
	for v := 1; v <= 6; v++ {
		diff := float64(counts[v]) - expected
		chi2 += diff * diff / expected
	}
	// 5 degrees of freedom; 35.9 ≈ p = 1e-6, so a fair die virtually never
	// fails while the modulo bias above scores ≈ 73.
	if chi2 > 35.9 {
		t.Fatalf("dice look biased: chi2=%.1f counts=%v", chi2, counts[1:])
	}
}

func TestSeededDiceIsDeterministic(t *testing.T) {
	a, b := NewSeededDice(7), NewSeededDice(7)
	for range 100 {
		if x, y := a.Roll(), b.Roll(); x != y || x < 1 || x > 6 {
			t.Fatalf("seeded dice diverged or out of range: %d %d", x, y)
		}
	}
}
