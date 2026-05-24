namespace UrduMeaning.Api.Models;

public class Correction
{
    public int Id { get; set; }
    public string Word { get; set; } = "";
    /// <summary>Nullable — anonymous users can flag too.</summary>
    public int? UserId { get; set; }
    /// <summary>translation | example | poetry | other</summary>
    public string Reason { get; set; } = "other";
    public string? Notes { get; set; }
    /// <summary>open | reviewed | dismissed</summary>
    public string Status { get; set; } = "open";
    public DateTime CreatedAt { get; set; }
}
