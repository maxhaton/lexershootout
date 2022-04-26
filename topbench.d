pragma(inline, false):
size_t dparseCount(string sourceCode)
{
    import dparse.lexer : StringCache, DLexer, LexerConfig, CommentBehavior, WhitespaceBehavior;
    import std.range;
    LexerConfig config;
    config.commentBehavior = CommentBehavior.intern;
    config.whitespaceBehavior = WhitespaceBehavior.skip;
    auto cache = StringCache(StringCache.defaultBucketCount);
    auto lexy = DLexer(sourceCode, config, &cache);

    return imported!"std.algorithm.searching".count(lexy);
}

size_t sdcCount(string sourceCode)
{
    //adapted from sdc lexer testsuite
    import source.dlexer, source.context, source.name, source.location;
    scope context = new Context;
    auto base = context.registerMixin(Location.init, sourceCode ~ '\0');
    auto l = lex(base, context);
	return imported!"std.algorithm.searching".count(l);
}
__gshared int cnt = 0;
size_t dmdFrontendCount(string sourceCode)
{
    import dmd.lexer;
    import std.conv, std.string;
    ++cnt;
    //This seems to be needed otherwise dmd string interning goes completely mad
    auto x = new Lexer(cnt.to!string.toStringz, sourceCode.ptr, 0, sourceCode.length, 0, 0);
    return imported!"std.algorithm.searching".count(x);
}
bool acceptHeuristic(size_t[] cnt)
    in(cnt.length == 3)
{
    import std.algorithm, std.math;
    cnt.sort();
    const firstTwoMean = 0.5 * (cast(double) cnt[2] + cast(double) cnt[1]);
    const lastPropDiff = abs(cnt[0] - firstTwoMean) / firstTwoMean;
    return lastPropDiff < 0.30;
}

void main(string[] args)
{
    import std.file, std.path, std.stdio;
    if (true) {
        imported!"dmd.globals".global.startGagging();
        string contents = readText(args[1]);
        import std.meta : AliasSeq;
        alias list = AliasSeq!(dparseCount, sdcCount, dmdFrontendCount);
        foreach (t; list)
        {
            import std.datetime.stopwatch;
            //This is required because one of the lexers is a bit naughty.
            //string copy = contents.idup;
            auto sw = StopWatch(AutoStart.no);
            sw.start();
            foreach(_; 0..100)
            {
                immutable copy = contents.idup;
                t(copy);
            }
            sw.stop();
            writeln(__traits(identifier, t), " -> ", sw.peek);
        }
        return;
    }
    auto f = dirEntries(buildPath(args[1]), SpanMode.shallow);
    uint cnt;
    uint disagreed;
    imported!"dmd.globals".global.startGagging();
    foreach(el; f)
    {
        if(extension(el) != ".d")
            continue;
        import std.file;

        try {
            string fileContents = readText(el);
            if (!fileContents)
                continue;
            const dpRes = dparseCount(fileContents.idup);
            const sdcRes = sdcCount(fileContents.idup);
            const dmdRes = dmdFrontendCount(fileContents.idup);
            ++cnt;

            if(acceptHeuristic([dpRes, sdcRes, dmdRes])) {
                
            } else {
                writefln("%s -> {libdparse: %u, sdc: %u, dmd: %u}", el, dpRes, sdcRes, dmdRes);
                ++disagreed;
            }
        } catch(Throwable e)
        {
            //writeln("Couldn't open " ~ el);
            //writeln(e.msg);
        } 
    }
    writefln("Finished! %u tests completed, they disagreed on %u", cnt, disagreed);
}

//0.887 for dmd alone