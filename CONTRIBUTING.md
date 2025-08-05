# Contributing to vltCoins

Thank you for your interest in contributing to the vltCoins stablecoin suite! This document provides guidelines for contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and inclusive in all interactions.

## How Can I Contribute?

### Reporting Bugs

- Use the GitHub issue tracker
- Provide detailed reproduction steps
- Include error messages and stack traces
- Specify your environment (OS, Node.js version, etc.)

### Suggesting Enhancements

- Use the GitHub issue tracker with the "enhancement" label
- Describe the feature and its benefits
- Consider implementation complexity
- Discuss with maintainers before major changes

### Submitting Code

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**:
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed
4. **Test your changes**:
   ```bash
   npm test
   npm run lint
   npm run audit
   ```
5. **Commit your changes**: `git commit -m 'Add amazing feature'`
6. **Push to your fork**: `git push origin feature/amazing-feature`
7. **Create a Pull Request**

## Development Guidelines

### Code Style

- Follow Solidity style guide
- Use meaningful variable and function names
- Add comprehensive comments for complex logic
- Keep functions focused and single-purpose

### Testing

- Write tests for all new functionality
- Ensure existing tests pass
- Add integration tests for cross-contract interactions
- Test edge cases and error conditions

### Security

- Follow security best practices
- Use reentrancy protection where needed
- Validate all inputs
- Consider gas optimization
- Test for common vulnerabilities

### Documentation

- Update README.md for user-facing changes
- Update ARCHITECTURE.md for architectural changes
- Add inline comments for complex logic
- Document any new configuration options

## Pull Request Process

1. **Update documentation** if needed
2. **Add tests** for new functionality
3. **Ensure all tests pass**
4. **Update CHANGELOG.md** with your changes
5. **Request review** from maintainers

## Review Process

- All PRs require at least one review
- Maintainers will review for:
  - Code quality and style
  - Security considerations
  - Test coverage
  - Documentation updates
- Address feedback before merging

## Getting Help

- Check existing issues and PRs
- Join our discussions
- Ask questions in GitHub issues
- Review the documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to vltCoins! 🚀 