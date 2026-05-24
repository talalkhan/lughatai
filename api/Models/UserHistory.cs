namespace UrduMeaning.Api.Models;

public class UserHistory
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Word { get; set; } = "";
    public DateTime LookedUpAt { get; set; }
}
