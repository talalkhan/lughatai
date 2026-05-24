namespace UrduMeaning.Api.Models;

public class UserFavorite
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string Word { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}
