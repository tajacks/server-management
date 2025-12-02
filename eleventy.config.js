import syntaxHighlight from "@11ty/eleventy-plugin-syntaxhighlight";

export default function(eleventyConfig) {
  // Add syntax highlighting plugin
  eleventyConfig.addPlugin(syntaxHighlight);

  // Passthrough copy for CSS
  eleventyConfig.addPassthroughCopy("src/css");

  // Create chapters collection - all markdown files in src/chapters
  eleventyConfig.addCollection("chapters", function(collectionApi) {
    return collectionApi.getFilteredByGlob("src/chapters/**/*.md")
      .sort((a, b) => {
        const aChapter = a.data.chapterNumber || 0;
        const bChapter = b.data.chapterNumber || 0;
        const aSection = a.data.sectionNumber || 0;
        const bSection = b.data.sectionNumber || 0;

        // Sort by chapter first, then by section
        if (aChapter !== bChapter) {
          return aChapter - bChapter;
        }
        return aSection - bSection;
      });
  });

  // Filter to get only chapter index pages (no sectionNumber)
  eleventyConfig.addFilter("chapterIndexesOnly", function(chapters) {
    return chapters.filter(page => !page.data.sectionNumber);
  });

  // Filter to get sections for a specific chapter
  eleventyConfig.addFilter("getChapterSections", function(chapters, chapterNum) {
    return chapters.filter(page =>
      page.data.chapterNumber === chapterNum && page.data.sectionNumber
    );
  });

  // Filter to get chapter index page by number
  eleventyConfig.addFilter("getChapterByNumber", function(chapters, chapterNum) {
    return chapters.find(page =>
      page.data.chapterNumber === chapterNum && !page.data.sectionNumber
    );
  });

  // Add previous/next page data to each chapter/section
  eleventyConfig.addCollection("chaptersWithNav", function(collectionApi) {
    const chapters = collectionApi.getFilteredByGlob("src/chapters/**/*.md")
      .sort((a, b) => {
        const aChapter = a.data.chapterNumber || 0;
        const bChapter = b.data.chapterNumber || 0;
        const aSection = a.data.sectionNumber || 0;
        const bSection = b.data.sectionNumber || 0;

        if (aChapter !== bChapter) {
          return aChapter - bChapter;
        }
        return aSection - bSection;
      });

    // Add previousPage and nextPage to each item
    chapters.forEach((page, index) => {
      page.data.previousPage = index > 0 ? chapters[index - 1] : null;
      page.data.nextPage = index < chapters.length - 1 ? chapters[index + 1] : null;
    });

    return chapters;
  });

  return {
    dir: {
      input: "src",
      output: "_site",
      includes: "_includes",
      data: "_data"
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk"
  };
}
