namespace UrduMeaning.Api.Models;

public class WordQueue
{
    public int Id { get; set; }
    public string Word { get; set; } = "";
    public string Status { get; set; } = "pending";
    public int Priority { get; set; } = 3;
    public int Attempts { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
