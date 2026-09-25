/// Model class representing a motivational quote.
class Quote {
  final String text;
  final String author;

  const Quote({
    required this.text,
    required this.author,
  });
}

/// Centralized repository of motivational quotes tailored for students & admission candidates.
const List<Quote> motivationalQuotes = [
  Quote(
    text: 'Success is no accident. It is hard work, perseverance, learning, studying, sacrifice and most of all, love of what you are doing.',
    author: 'Pelé',
  ),
  Quote(
    text: 'The future belongs to those who believe in the beauty of their dreams.',
    author: 'Eleanor Roosevelt',
  ),
  Quote(
    text: 'Push yourself, because no one else is going to do it for you.',
    author: 'Anonymous',
  ),
  Quote(
    text: 'Success is the sum of small efforts, repeated day in and day out.',
    author: 'Robert Collier',
  ),
  Quote(
    text: 'It always seems impossible until it is done.',
    author: 'Nelson Mandela',
  ),
  Quote(
    text: 'Don\'t watch the clock; do what it does. Keep going.',
    author: 'Sam Levenson',
  ),
  Quote(
    text: 'There are no secrets to success. It is the result of preparation, hard work, and learning from failure.',
    author: 'Colin Powell',
  ),
  Quote(
    text: 'Strive for progress, not perfection.',
    author: 'Anonymous',
  ),
  Quote(
    text: 'The expert in anything was once a beginner.',
    author: 'Helen Hayes',
  ),
  Quote(
    text: 'You don\'t have to be great to start, but you have to start to be great.',
    author: 'Zig Ziglar',
  ),
  Quote(
    text: 'Hard work beats talent when talent doesn\'t work hard.',
    author: 'Tim Notke',
  ),
  Quote(
    text: 'Your focus determines your reality. Stay disciplined and keep pushing forward.',
    author: 'George Lucas',
  ),
  Quote(
    text: 'Believe you can and you\'re halfway there.',
    author: 'Theodore Roosevelt',
  ),
  Quote(
    text: 'Failure is not the opposite of success; it\'s part of success.',
    author: 'Arianna Huffington',
  ),
  Quote(
    text: 'Dreams don\'t work unless you do.',
    author: 'John C. Maxwell',
  ),
];
