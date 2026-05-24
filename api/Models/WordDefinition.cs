namespace UrduMeaning.Api.Models;

public class WordDefinition
{
    public int Id { get; set; }
    public string Word { get; set; } = "";
    public string WordLower { get; set; } = "";
    public string Data { get; set; } = "{}";
    public int LookupCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
