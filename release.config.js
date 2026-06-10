module.exports = {
    plugins: [
        ['@semantic-release/commit-analyzer', {
            'preset': 'angular',
            // having version increments and builds for these commit types is valuable
            'releaseRules': [
                {'type': 'perf', 'release': 'patch'},
                {'type': 'docs', 'release': 'patch'},
                {'type': 'style', 'release': 'patch'},
                {'type': 'refactor', 'release': 'patch'},
                {'type': 'test', 'release': 'patch'},
                {'type': 'chore', 'release': 'patch'},
                {'type': 'ci', 'release': 'patch'},
            ],
        }],
        '@semantic-release/release-notes-generator',
        ['@semantic-release/changelog', {
            'changelogFile': 'changelog.md',
        }],
        ['@semantic-release/git', {
            // alt-tab-free [depaywall]: 'appcast.xml' REMOVED from assets (PLAN §3.3/§4.3). The fork
            // publishes the Sparkle feed OUT OF TREE (gh-pages) via scripts/update_appcast.sh, and
            // appcast.xml is removed from the tree. If it stayed here, semantic-release would try to
            // commit the now-untracked file back every release.
            'assets': [
                'changelog.md',
                'README.md',
            ],
        }],
    ],
}
