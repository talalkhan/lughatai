namespace UrduMeaning.Api.Models;

public class ApprovedWord
{
    public string Word { get; set; } = "";
    public string Source { get; set; } = "manual";
    public int Priority { get; set; } = 3;
    public DateTime CreatedAt { get; set; }
}
