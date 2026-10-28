import { slug } from './slug'

test('slug lowercases', () => {
  expect(slug('Ab')).toBe('ab')
})

test('slug lowercases again', () => {
  expect(slug('Ab')).toBe('ab')
})
