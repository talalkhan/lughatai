# Word Lists

Domain-specific word lists for expanding the LughatAI database beyond the initial 10k COCA seed.

## How to add a list

```powershell
# Queue with Sonnet quality (Priority 1) — for important/rich vocabulary
.\scripts\add_words.ps1 -File scripts\words\islamic_religious.txt -Priority 1

# Queue with Haiku quality (Priority 2) — for bulk vocabulary
.\scripts\add_words.ps1 -File scripts\words\technology.txt -Priority 2
```

Then make sure the API is running with `BatchProcessor:Enabled = true` and watch with `.\scripts\monitor_queue.ps1`.

## Existing lists

| File | Words | Recommended Priority | Notes |
|------|-------|---------------------|-------|
| `islamic_religious.txt` | ~90 | 1 (Sonnet) | Core faith & moral vocabulary, very high value for Urdu speakers |
| `emotions_psychology.txt` | ~80 | 1 (Sonnet) | Translates richly into Urdu — melancholy, nostalgia, longing etc. |
| `academic_formal.txt` | ~120 | 2 (Haiku) | Formal English used in Pakistani universities & newspapers |
| `technology.txt` | ~90 | 2 (Haiku) | Modern tech & digital society vocab |

## File format

Plain text, one word or phrase per line. Lines starting with `#` are comments and are ignored.

```
# This is a comment
ephemeral
melancholy
artificial intelligence
quantum computing
```

## Adding your own list

1. Create a new `.txt` file in this directory
2. Add words, one per line
3. Run `add_words.ps1` pointing at your file
4. Update this README with the new entry

## Priority guide

| Priority | Model | Use for |
|----------|-------|---------|
| 1 | Claude Sonnet | Important words where quality matters most — religious, emotional, literary |
| 2 | Claude Haiku | General expansion — academic, technical, professional |
| 3 | Claude Haiku | Low-priority / experimental lists |
