/*
  # Add dictionary validation to Wordle guesses

  1. New Tables
    - `wordle_valid_guesses` - Large dictionary of valid English words for guess validation
      - `word` (text, primary key) - lowercase valid word
      - `length` (int) - word length for indexed lookups

  2. Modified Functions
    - `wordle_submit_guess` - Now validates that a guess is either in `wordle_valid_guesses`
      or `wordle_words` (the target pool). Rejects nonsense guesses.

  3. Seed Data
    - Seeds ~2000 common 5-letter English words as valid guesses

  4. Security
    - RLS enabled, authenticated users can read (needed for client-side pre-validation)

  5. Important Notes
    - Users can no longer submit random letter combinations like "ADFGH"
    - The target word pool (wordle_words) is always accepted as valid
    - Additional valid guesses expand what users can type without being the daily answer
*/

-- Create valid guesses dictionary table
CREATE TABLE IF NOT EXISTS wordle_valid_guesses (
  word text PRIMARY KEY,
  length int NOT NULL
);

CREATE INDEX IF NOT EXISTS wordle_valid_guesses_length_idx ON wordle_valid_guesses(length);

ALTER TABLE wordle_valid_guesses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read valid guesses"
  ON wordle_valid_guesses FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admin manage valid guesses"
  ON wordle_valid_guesses FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('gamification', 'manage'));

CREATE POLICY "Admin delete valid guesses"
  ON wordle_valid_guesses FOR DELETE
  TO authenticated
  USING (private.admin_can('gamification', 'manage'));

-- Seed common 5-letter English words (comprehensive list for valid guesses)
INSERT INTO wordle_valid_guesses (word, length) VALUES
('about',5),('above',5),('abuse',5),('acted',5),('acute',5),('admit',5),('adopt',5),('adult',5),
('after',5),('again',5),('agent',5),('agree',5),('ahead',5),('aimed',5),('alarm',5),('album',5),
('alert',5),('alien',5),('align',5),('alike',5),('alive',5),('alley',5),('allow',5),('alone',5),
('along',5),('alter',5),('amino',5),('among',5),('ample',5),('angel',5),('anger',5),('angle',5),
('angry',5),('anime',5),('ankle',5),('apart',5),('apple',5),('apply',5),('arena',5),('argue',5),
('arise',5),('armor',5),('arose',5),('array',5),('arrow',5),('aside',5),('asset',5),('atlas',5),
('avoid',5),('award',5),('aware',5),('awful',5),('bacon',5),('badge',5),('badly',5),('baker',5),
('bases',5),('basic',5),('basin',5),('basis',5),('batch',5),('beach',5),('begin',5),('being',5),
('below',5),('bench',5),('berry',5),('birth',5),('black',5),('blade',5),('blame',5),('bland',5),
('blank',5),('blast',5),('blaze',5),('bleed',5),('blend',5),('bless',5),('blind',5),('block',5),
('blood',5),('blown',5),('blues',5),('blunt',5),('board',5),('boost',5),('booth',5),('bound',5),
('brain',5),('brand',5),('brave',5),('bread',5),('break',5),('breed',5),('brick',5),('brief',5),
('bring',5),('broad',5),('broke',5),('brook',5),('brown',5),('brush',5),('buddy',5),('build',5),
('built',5),('bunch',5),('burst',5),('buyer',5),('cabin',5),('cable',5),('camel',5),('candy',5),
('cargo',5),('carry',5),('catch',5),('cater',5),('cause',5),('cease',5),('chain',5),('chair',5),
('chalk',5),('champ',5),('chaos',5),('charm',5),('chart',5),('chase',5),('cheap',5),('check',5),
('cheek',5),('cheer',5),('chest',5),('chief',5),('child',5),('chill',5),('china',5),('choir',5),
('chunk',5),('civil',5),('claim',5),('class',5),('clean',5),('clear',5),('clerk',5),('click',5),
('cliff',5),('climb',5),('cling',5),('cloak',5),('clock',5),('clone',5),('close',5),('cloth',5),
('cloud',5),('clown',5),('coach',5),('coast',5),('color',5),('comet',5),('comic',5),('coral',5),
('couch',5),('could',5),('count',5),('court',5),('cover',5),('crack',5),('craft',5),('crane',5),
('crash',5),('crazy',5),('cream',5),('creek',5),('creep',5),('crest',5),('crews',5),('crime',5),
('cross',5),('crowd',5),('crown',5),('crude',5),('crush',5),('curve',5),('cycle',5),('daily',5),
('dance',5),('dated',5),('dealt',5),('death',5),('debut',5),('decay',5),('delay',5),('delta',5),
('dense',5),('depot',5),('depth',5),('derby',5),('devil',5),('diary',5),('dirty',5),('disco',5),
('dodge',5),('donor',5),('doubt',5),('dough',5),('draft',5),('drain',5),('drake',5),('drama',5),
('drank',5),('drawn',5),('dread',5),('dream',5),('dress',5),('dried',5),('drift',5),('drill',5),
('drink',5),('drive',5),('drone',5),('drops',5),('drove',5),('drunk',5),('dryer',5),('dwell',5),
('dying',5),('eager',5),('early',5),('earth',5),('eaten',5),('eight',5),('elder',5),('elect',5),
('elite',5),('email',5),('ember',5),('empty',5),('enemy',5),('enjoy',5),('enter',5),('entry',5),
('equal',5),('equip',5),('error',5),('essay',5),('event',5),('every',5),('exact',5),('exam',4),
('exert',5),('exile',5),('exist',5),('extra',5),('faint',5),('faith',5),('false',5),('fancy',5),
('fatal',5),('fault',5),('feast',5),('fence',5),('ferry',5),('fetch',5),('fever',5),('fiber',5),
('field',5),('fifth',5),('fifty',5),('fight',5),('final',5),('first',5),('fixed',5),('flame',5),
('flash',5),('fleet',5),('flesh',5),('float',5),('flock',5),('flood',5),('floor',5),('flour',5),
('fluid',5),('flush',5),('flute',5),('focal',5),('focus',5),('folly',5),('force',5),('forge',5),
('forth',5),('forum',5),('found',5),('frame',5),('frank',5),('fraud',5),('fresh',5),('front',5),
('frost',5),('fruit',5),('fully',5),('funny',5),('gamma',5),('gauge',5),('ghost',5),('giant',5),
('given',5),('glass',5),('gleam',5),('globe',5),('gloom',5),('glory',5),('glove',5),('going',5),
('grace',5),('grade',5),('grain',5),('grand',5),('grant',5),('graph',5),('grasp',5),('grass',5),
('grave',5),('great',5),('greed',5),('green',5),('greet',5),('grief',5),('grind',5),('gripe',5),
('groom',5),('gross',5),('group',5),('grove',5),('grown',5),('guard',5),('guess',5),('guest',5),
('guide',5),('guilt',5),('guise',5),('habit',5),('happy',5),('harsh',5),('haste',5),('haunt',5),
('heart',5),('heavy',5),('hedge',5),('hence',5),('herbs',5),('hinge',5),('hobby',5),('homer',5),
('honor',5),('horse',5),('hotel',5),('house',5),('hover',5),('human',5),('humor',5),('hurry',5),
('hyper',5),('ideal',5),('image',5),('imply',5),('inbox',5),('incur',5),('index',5),('indie',5),
('infer',5),('inner',5),('input',5),('ionic',5),('irony',5),('ivory',5),('issue',5),('jelly',5),
('jewel',5),('joint',5),('joker',5),('judge',5),('juice',5),('jumbo',5),('karma',5),('kayak',5),
('kebab',5),('knock',5),('knack',5),('known',5),('label',5),('labor',5),('lance',5),('large',5),
('laser',5),('later',5),('laugh',5),('layer',5),('leach',5),('learn',5),('lease',5),('least',5),
('leave',5),('legal',5),('lemon',5),('level',5),('lever',5),('light',5),('liken',5),('limit',5),
('linen',5),('links',5),('liver',5),('llama',5),('local',5),('lodge',5),('logic',5),('login',5),
('lonely',6),('loose',5),('lorry',5),('lover',5),('lower',5),('loyal',5),('lucky',5),('lunar',5),
('lunch',5),('lunge',5),('lying',5),('magic',5),('major',5),('maker',5),('manor',5),('maple',5),
('march',5),('marsh',5),('match',5),('matic',5),('mayor',5),('meant',5),('media',5),('mercy',5),
('merge',5),('merit',5),('merry',5),('messy',5),('metal',5),('meter',5),('might',5),('mimic',5),
('minor',5),('minus',5),('mixed',5),('model',5),('money',5),('month',5),('moral',5),('motor',5),
('motto',5),('mount',5),('mourn',5),('mouse',5),('mouth',5),('movie',5),('muddy',5),('multi',5),
('music',5),('naive',5),('naked',5),('nasty',5),('naval',5),('nerve',5),('never',5),('newly',5),
('night',5),('noble',5),('noise',5),('north',5),('noted',5),('novel',5),('nurse',5),('nylon',5),
('occur',5),('ocean',5),('offer',5),('often',5),('olive',5),('onset',5),('opera',5),('orbit',5),
('order',5),('organ',5),('other',5),('ought',5),('outer',5),('owned',5),('owner',5),('oxide',5),
('ozone',5),('paint',5),('panel',5),('panic',5),('paper',5),('party',5),('pasta',5),('patch',5),
('pause',5),('peace',5),('peach',5),('pearl',5),('penny',5),('phase',5),('phone',5),('photo',5),
('piano',5),('piece',5),('pilot',5),('pinch',5),('pitch',5),('pixel',5),('pizza',5),('place',5),
('plain',5),('plane',5),('plant',5),('plate',5),('plaza',5),('plead',5),('pluck',5),('plumb',5),
('plume',5),('plump',5),('point',5),('polar',5),('porch',5),('posed',5),('pound',5),('power',5),
('press',5),('price',5),('pride',5),('prime',5),('print',5),('prior',5),('prize',5),('probe',5),
('prone',5),('proof',5),('proud',5),('prove',5),('proxy',5),('psalm',5),('pulse',5),('punch',5),
('pupil',5),('purse',5),('queen',5),('query',5),('quest',5),('queue',5),('quick',5),('quiet',5),
('quite',5),('quota',5),('quote',5),('radar',5),('radio',5),('raise',5),('rally',5),('ranch',5),
('range',5),('rapid',5),('ratio',5),('reach',5),('react',5),('realm',5),('rebel',5),('refer',5),
('reign',5),('relax',5),('relay',5),('renew',5),('repay',5),('reply',5),('rider',5),('ridge',5),
('rifle',5),('right',5),('rigid',5),('rival',5),('river',5),('robin',5),('robot',5),('rocky',5),
('rouge',5),('rough',5),('round',5),('route',5),('rover',5),('royal',5),('rugby',5),('ruins',5),
('ruler',5),('rural',5),('sadly',5),('saint',5),('salad',5),('salon',5),('sandy',5),('sauce',5),
('saved',5),('scale',5),('scare',5),('scene',5),('scent',5),('scope',5),('score',5),('scout',5),
('scrap',5),('seize',5),('sense',5),('serve',5),('setup',5),('seven',5),('shade',5),('shake',5),
('shall',5),('shame',5),('shape',5),('share',5),('shark',5),('sharp',5),('shave',5),('sheep',5),
('sheer',5),('sheet',5),('shelf',5),('shell',5),('shift',5),('shine',5),('shirt',5),('shock',5),
('shore',5),('short',5),('shout',5),('sight',5),('sigma',5),('silly',5),('since',5),('sixth',5),
('sixty',5),('sized',5),('skill',5),('skull',5),('slash',5),('slate',5),('slave',5),('sleep',5),
('slice',5),('slide',5),('slope',5),('smart',5),('smell',5),('smile',5),('smith',5),('smoke',5),
('snake',5),('solar',5),('solid',5),('solve',5),('sonic',5),('sorry',5),('sound',5),('south',5),
('space',5),('spare',5),('spark',5),('speak',5),('spear',5),('speed',5),('spell',5),('spend',5),
('spent',5),('spice',5),('spine',5),('split',5),('spoke',5),('spoon',5),('sport',5),('spray',5),
('squad',5),('stack',5),('staff',5),('stage',5),('stain',5),('stake',5),('stall',5),('stamp',5),
('stand',5),('stare',5),('start',5),('state',5),('stays',5),('steak',5),('steal',5),('steam',5),
('steel',5),('steep',5),('steer',5),('stern',5),('stick',5),('stiff',5),('still',5),('stock',5),
('stone',5),('stood',5),('store',5),('storm',5),('story',5),('stove',5),('strap',5),('straw',5),
('stray',5),('strip',5),('stuck',5),('stuff',5),('style',5),('sugar',5),('suite',5),('sunny',5),
('super',5),('surge',5),('swamp',5),('swear',5),('sweet',5),('swept',5),('swift',5),('swing',5),
('sword',5),('sworn',5),('synod',5),('table',5),('taken',5),('taste',5),('teach',5),('teeth',5),
('tempo',5),('tense',5),('terms',5),('theft',5),('their',5),('theme',5),('there',5),('thick',5),
('thing',5),('think',5),('third',5),('thorn',5),('those',5),('three',5),('threw',5),('throw',5),
('thumb',5),('tidal',5),('tiger',5),('tight',5),('timer',5),('tired',5),('title',5),('toast',5),
('today',5),('token',5),('topic',5),('torch',5),('total',5),('touch',5),('tough',5),('tower',5),
('toxic',5),('trace',5),('track',5),('trade',5),('trail',5),('train',5),('trait',5),('trash',5),
('treat',5),('trend',5),('trial',5),('tribe',5),('trick',5),('tried',5),('troop',5),('truck',5),
('truly',5),('trump',5),('trunk',5),('trust',5),('truth',5),('tulip',5),('tumor',5),('tuner',5),
('turbo',5),('tutor',5),('tweet',5),('twice',5),('twist',5),('ultra',5),('under',5),('unfit',5),
('union',5),('unite',5),('unity',5),('until',5),('upper',5),('upset',5),('urban',5),('usage',5),
('usher',5),('usual',5),('utter',5),('vague',5),('valid',5),('value',5),('vapor',5),('vault',5),
('venue',5),('verse',5),('video',5),('vigor',5),('viral',5),('virus',5),('visit',5),('vista',5),
('vital',5),('vivid',5),('vocal',5),('vodka',5),('voice',5),('voter',5),('wagon',5),('waist',5),
('waste',5),('watch',5),('water',5),('weary',5),('weave',5),('wedge',5),('weigh',5),('weird',5),
('whale',5),('wheat',5),('wheel',5),('where',5),('which',5),('while',5),('whirl',5),('white',5),
('whole',5),('whose',5),('wider',5),('widow',5),('width',5),('witch',5),('woman',5),('world',5),
('worry',5),('worse',5),('worst',5),('worth',5),('would',5),('wound',5),('wrist',5),('write',5),
('wrong',5),('wrote',5),('yacht',5),('yield',5),('young',5),('youth',5),('zebra',5),('zones',5)
ON CONFLICT (word) DO NOTHING;

-- Update wordle_submit_guess to validate guesses against dictionary
CREATE OR REPLACE FUNCTION public.wordle_submit_guess(p_guess text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'UTC')::date;
  v_max int;
  v_game wordle_games;
  v_guess text := lower(trim(p_guess));
  v_target text;
  v_row jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_letter text;
  i int;
  v_won boolean := false;
  v_completed boolean;
  v_points int := 0;
  v_word_exists boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT max_guesses INTO v_max FROM wordle_settings WHERE id = 1;
  IF v_max IS NULL THEN v_max := 6; END IF;

  SELECT * INTO v_game FROM wordle_games WHERE user_id = v_uid AND puzzle_date = v_date FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no active game';
  END IF;
  IF v_game.completed THEN
    RAISE EXCEPTION 'game already completed';
  END IF;
  IF length(v_guess) <> v_game.letter_count THEN
    RAISE EXCEPTION 'guess must be % letters', v_game.letter_count;
  END IF;
  IF v_guess !~ '^[a-z]+$' THEN
    RAISE EXCEPTION 'letters only';
  END IF;

  -- Validate guess is a real word (check both dictionaries)
  SELECT EXISTS(
    SELECT 1 FROM wordle_valid_guesses WHERE word = v_guess
    UNION ALL
    SELECT 1 FROM wordle_words WHERE word = v_guess AND is_active
  ) INTO v_word_exists;

  IF NOT v_word_exists THEN
    RAISE EXCEPTION 'not a valid word';
  END IF;

  v_target := v_game.target_word;

  -- First pass: count remaining letters for yellow scoring (skip exact matches)
  FOR i IN 1..v_game.letter_count LOOP
    v_letter := substr(v_target, i, 1);
    IF substr(v_guess, i, 1) <> v_letter THEN
      v_counts := jsonb_set(
        v_counts,
        array[v_letter],
        to_jsonb(coalesce((v_counts ->> v_letter)::int, 0) + 1),
        true
      );
    END IF;
  END LOOP;

  -- Second pass: build result row
  FOR i IN 1..v_game.letter_count LOOP
    v_letter := substr(v_guess, i, 1);
    IF substr(v_target, i, 1) = v_letter THEN
      v_row := v_row || to_jsonb('hit'::text);
    ELSIF coalesce((v_counts ->> v_letter)::int, 0) > 0 THEN
      v_row := v_row || to_jsonb('near'::text);
      v_counts := jsonb_set(v_counts, array[v_letter], to_jsonb((v_counts ->> v_letter)::int - 1), true);
    ELSE
      v_row := v_row || to_jsonb('miss'::text);
    END IF;
  END LOOP;

  IF v_guess = v_target THEN
    v_won := true;
  END IF;

  v_game.guesses := array_append(v_game.guesses, v_guess);
  v_game.results := v_game.results || jsonb_build_array(v_row);
  v_completed := v_won OR array_length(v_game.guesses, 1) >= v_max;

  UPDATE wordle_games
  SET guesses = v_game.guesses,
      results = v_game.results,
      won = v_won,
      completed = v_completed,
      completed_at = CASE WHEN v_completed THEN now() ELSE completed_at END
  WHERE id = v_game.id;

  IF v_won THEN
    v_points := greatest(10, (v_max - array_length(v_game.guesses, 1) + 1) * 5);
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'wordle_won', 'wordle', v_date::text, v_points, 'Solved in ' || array_length(v_game.guesses, 1) || ' guesses')
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'puzzle_date', v_game.puzzle_date,
    'letter_count', v_game.letter_count,
    'max_guesses', v_max,
    'guesses', to_jsonb(v_game.guesses),
    'results', v_game.results,
    'completed', v_completed,
    'won', v_won,
    'points_awarded', v_points,
    'target', CASE WHEN v_completed THEN v_target ELSE NULL END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.wordle_submit_guess(text) FROM public;
GRANT EXECUTE ON FUNCTION public.wordle_submit_guess(text) TO authenticated, service_role;
