import java.util.Optional;
import java.util.StringTokenizer;
import java.util.function.BiFunction;

class Markdown {
    private boolean activeList;
    private StringBuilder output;

    String parse(String markdown) {
        activeList = false;
        output = new StringBuilder();
        parseDocument(markdown);
        return output.toString();
    }

    private void parseDocument(String markdown) {
        String[] lines = markdown.split("\n");

        for (String line : lines) {
             parseLine(line).ifPresent(output::append);
        }

        encloseList().ifPresent(output::append);
    }

    private Optional<String> parseLine(String line) {
        return parseHeader(line)
                .or(() -> parseListItem(line))
                .or(() -> bothOrAny(
                        encloseList(),
                        parseParagraph(line), String::concat))
                .or(() -> Optional.of(line));
    }

    private Optional<String> encloseList() {
        if (this.activeList) {
            this.activeList = false;
            return Optional.of("</ul>");
        }

        return Optional.empty();
    }

    private Optional<String> parseHeader(String markdown) {
        int count = 0;

        for (int i = 0; i < markdown.length() && markdown.charAt(i) == '#'; i++) 
        {
            count++;
        }

        if (count == 0 || count > 6) {
            return Optional.empty();
        }

        return Optional.of(buildHeader(markdown, count));
    }

    private String buildHeader(String markdown, int count) {
        return "<h%d>%s</h%d>".formatted(
                count,
                markdown.substring(count + 1),
                count
        );
    }

    private Optional<String> parseListItem(String markdown) {
        if (markdown.startsWith("*")) {
            String skipAsterisk = markdown.substring(2);
            String listItemString = parseHighlighting(skipAsterisk);

            return Optional.of(buildListBegin() + buildListItem(listItemString));
        }

        return Optional.empty();
    }

    private String buildListItem(String listItemString) {
        return "<li>" + listItemString + "</li>";
    }

    private String buildListBegin() {
        if (!activeList) {
            this.activeList = true;
            return "<ul>";
        }
        return "";
    }

    private Optional<String> parseParagraph(String markdown) {
        String paragraph = parseHighlighting(markdown);
        return Optional.of(buildParagraph(paragraph));
    }

    private String buildParagraph(String paragraph) {
        return "<p>" + paragraph + "</p>";
    }

    private String parseHighlighting(String markdown) {
        String result = parseBold(markdown);
        result = parseItalic(result);
        return result;
    }

    private String parseItalic(String workingOn) {
        String lookingFor = "_(.+)_";
        String update = "<em>$1</em>";
        return workingOn.replaceAll(lookingFor, update);
    }

    private String parseBold(String markdown) {
        String lookingFor = "__(.+)__";
        String update = "<strong>$1</strong>";
        return markdown.replaceAll(lookingFor, update);
    }

    /**
     * Helper method.
     * The method takes two optional o1 and o2,
     * if both are present it applies a combiner to boxed values and wraps it back to Optional.
     * Otherwise, the method will return o1 combined with o2 using Optional::or method.
     */
    private <T> Optional<T> bothOrAny(Optional<T> o1, Optional<T> o2, BiFunction<T,T,T> combiner){
        if(o1.isPresent() && o2.isPresent()) {
            return Optional.of(combiner.apply(o1.get(), o2.get()));
        }

        return o1.or(() -> o2);
    }
}
