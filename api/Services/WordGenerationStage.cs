namespace UrduMeaning.Api.Services;

public enum WordGenerationStage
{
    Core,
    Enriched
}

public static class WordGenerationStageExtensions
{
    public static string ToMetaValue(this WordGenerationStage stage) =>
        stage switch
        {
            WordGenerationStage.Core => "core",
            _ => "enriched"
        };
}
