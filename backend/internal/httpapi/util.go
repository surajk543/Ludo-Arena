package httpapi

import "encoding/json"

// structToMap converts a JSON-tagged struct into a map (one level).
func structToMap(v any) map[string]any {
	raw, err := json.Marshal(v)
	if err != nil {
		return map[string]any{}
	}
	out := map[string]any{}
	_ = json.Unmarshal(raw, &out)
	return out
}
