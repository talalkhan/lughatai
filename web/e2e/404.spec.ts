import { test, expect } from '@playwright/test'

test.describe('404 and error handling', () => {
  test('unknown word URL shows a friendly word-not-found page', async ({ page }) => {
    await page.goto('/word/xyzxyz123notaword')

    // Should NOT show a raw error or crash
    await expect(page.locator('body')).not.toContainText('Internal Server Error')
    await expect(page.locator('body')).not.toContainText('Unhandled Runtime Error')

    // Should show a friendly message mentioning the word or "not found"
    const message = page.locator('body')
    const hasNotFound = await message.getByText(/not found|couldn't find|does not exist/i).count()
    expect(hasNotFound).toBeGreaterThan(0)

    // Should contain a search bar so the user can try again
    const searchInput = page.getByRole('textbox', { name: /search/i })
    await expect(searchInput).toBeVisible()
  })

  test('navigating to /word/xyzxyz123 returns appropriate HTTP status or renders 404 page', async ({ page }) => {
    const response = await page.goto('/word/xyzxyz123notaword')
    // Next.js notFound() triggers 404 status
    expect([200, 404]).toContain(response?.status())

    // Either way, UI should not show "Server Error"
    await expect(page.locator('body')).not.toContainText('500')
  })

  test('app-level 404 for completely unknown routes shows not-found page', async ({ page }) => {
    await page.goto('/this-route-does-not-exist-at-all')

    await expect(page.locator('body')).not.toContainText('Internal Server Error')
    // Next.js root not-found should render
    const notFoundIndicator = page.locator('body').getByText(/not found|page.*not found|404/i)
    await expect(notFoundIndicator.first()).toBeVisible({ timeout: 5000 })
  })

  test('API being down shows friendly error (not raw error) on word page', async ({ page }) => {
    // Mock the API to return a 503
    await page.route('**/api/word/**', route =>
      route.fulfill({ status: 503, body: JSON.stringify({ error: 'Service unavailable' }) })
    )

    await page.goto('/word/serenity')

    // Should show friendly error, not raw exception
    await expect(page.locator('body')).not.toContainText('Unhandled Runtime Error')
    await expect(page.locator('body')).not.toContainText('fetch failed')

    const errorMessage = page.getByText(/something went wrong|unavailable|try again/i)
    await expect(errorMessage.first()).toBeVisible({ timeout: 5000 })
  })
})
