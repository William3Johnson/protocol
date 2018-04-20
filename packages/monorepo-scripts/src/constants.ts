import * as path from 'path';

export const constants = {
    monorepoRootPath: path.join(__dirname, '../../..'),
    stagingWebsite: 'http://staging-0xproject.s3-website-us-east-1.amazonaws.com',
    lernaExecutable: './node_modules/lerna/bin/lerna.js',
    githubPersonalAccessToken: process.env.GITHUB_PERSONAL_ACCESS_TOKEN_0X_JS,
};
