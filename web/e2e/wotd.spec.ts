import { test, expect } from '@playwright/test'

test.describe('Word of the Day', () => {
  test('WOTD card is visible on home page', async ({ page }) => {
    await page.goto('/')

    // WOTD section heading
    const wotdSection = page.locator(
      '[data-testid="wotd"], section:has-text("Word of the Day"), :text("Word of the Day")'
    ).first()
    await expect(wotdSection).toBeVisible({ timeout: 8000 })

    // English word in the card
    const wordHeading = page.locator('[data-testid="wotd"] h2, [data-testid="wotd"] h3').first()
    await expect(wordHeading).toBeVisible()
    await expect(wordHeading).not.toBeEmpty()
  })

  test('WOTD card contains a Urdu translation in Nastaliq', async ({ page }) => {
    await page.goto('/')

    const wotdCard = page.locator('[data-testid="wotd"]').first()
    await expect(wotdCard).toBeVisible({ timeout: 8000 })

    const urduText = wotdCard.locator('[lang="ur"], [dir="rtl"]').first()
    await expect(urduText).toBeVisible()
    await expect(urduText).not.toBeEmpty()
  })

  test('WOTD "See full definition" link navigates to word detail page', async ({ page }) => {
    await page.goto('/')

    const wotdCard = page.locator('[data-testid="wotd"]').first()
    await expect(wotdCard).toBeVisible({ timeout: 8000 })

    const detailLink = wotdCard.getByRole('link', { name: /full definition|see more|learn more/i })
    await expect(detailLink).toBeVisible()

    const href = await detailLink.getAttribute('href')
    expect(href).toMatch(/\/word\/\w+/)
  })

  test('WOTD returns the same word all day', async ({ page }) => {
    await page.goto('/')
    const wotdCard = page.locator('[data-testid="wotd"]').first()
    await expect(wotdCard).toBeVisible({ timeout: 8000 })

    const wordText = await wotdCard.locator('h2, h3').first().textContent()

    // Reload and check same word appears
    await page.reload()
    await expect(wotdCard).toBeVisible({ timeout: 8000 })
    const wordTextAfterReload = await wotdCard.locator('h2, h3').first().textContent()

    expect(wordText?.trim()).toBe(wordTextAfterReload?.trim())
  })
})
