import { HtmlBasePlugin } from "@11ty/eleventy";

export default function (eleventyConfig) {
  eleventyConfig.addPlugin(HtmlBasePlugin);
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });
}

export const config = {
  dir: {
    input: "src",
    includes: "_includes",
    output: "_site"
  },
  htmlTemplateEngine: "njk",
  markdownTemplateEngine: "njk",
  pathPrefix: "/mutelet/"
};
