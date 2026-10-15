import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { asc, count, eq } from 'drizzle-orm';
import { openDatabase, type Db } from '../src/db/client.js';
import { aftercareTemplates, appointmentServices, appointments, services } from '../src/db/schema.js';
import { seedDatabase } from '../src/db/seed.js';
import { createClient } from '../src/domain/clients.js';
import { parseVariants } from '../src/lib/serialize.js';
import {
  importServices,
  parseArgs,
  prettifyName,
  splitPrice,
  type ServiceImportOptions,
} from '../src/scripts/import-services.js';
import { importAppointments, type VisitImportRecord } from '../src/scripts/import-appointments.js';
import { PRICE_LIST } from '../src/scripts/price-list.js';

const NOW = Date.parse('2026-10-15T12:00:00Z');
const BEFORE = NOW - 86_400_000;
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0xff, 0xd9]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x00]);

type ServiceInsert = typeof services.$inferInsert;

let tmp: string;
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mikan-import-services-'));
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function setup() {
  const { db, sqlite } = openDatabase(':memory:');
  seedDatabase(db, { admin: { login: 'admin', password: 'secret123', name: 'Админ' } });
  const imagesDir = path.join(tmp, 'images');
  fs.mkdirSync(imagesDir);
  const opts: ServiceImportOptions = {
    apply: true,
    updateExisting: false,
    linkHistory: false,
    imagesDir,
    uploadsDir: path.join(tmp, 'data', 'uploads'),
  };
  const clientId = createClient(db, { name: 'Анна', phone: null, source: 'yclients' }).id;
  return { db, sqlite, opts, clientId };
}

function addService(db: Db, values: Pick<ServiceInsert, 'name' | 'category' | 'price' | 'durationMin'> & Partial<ServiceInsert>) {
  return db
    .insert(services)
    .values({ priceFrom: false, active: true, sort: 0, createdAt: BEFORE, updatedAt: BEFORE, ...values })
    .returning()
    .get();
}

function addAppointment(db: Db, clientId: number, title: string | null, price: number) {
  return db
    .insert(appointments)
    .values({
      clientId,
      masterId: 1,
      serviceId: null,
      title,
      startsAt: BEFORE,
      endsAt: BEFORE + 3_600_000,
      status: 'completed',
      price,
      deposit: 0,
      createdAt: BEFORE,
      updatedAt: BEFORE,
    })
    .returning()
    .get();
}

const allServices = (db: Db) => db.select().from(services).orderBy(asc(services.id)).all();
const serviceNamed = (db: Db, name: string) => db.select().from(services).where(eq(services.name, name)).get()!;
const serviceById = (db: Db, id: number) => db.select().from(services).where(eq(services.id, id)).get()!;
const appointmentById = (db: Db, id: number) => db.select().from(appointments).where(eq(appointments.id, id)).get()!;
const linesOf = (db: Db, appointmentId: number) =>
  db
    .select({
      serviceId: appointmentServices.serviceId,
      name: appointmentServices.name,
      price: appointmentServices.price,
      durationMin: appointmentServices.durationMin,
      position: appointmentServices.position,
    })
    .from(appointmentServices)
    .where(eq(appointmentServices.appointmentId, appointmentId))
    .orderBy(asc(appointmentServices.position))
    .all();
const lineCount = (db: Db) => db.select({ n: count() }).from(appointmentServices).get()!.n;
const entryByKey = (key: string) => PRICE_LIST.find((e) => e.key === key)!;
const uploadedFiles = (dir: string) => (fs.existsSync(dir) ? fs.readdirSync(dir) : []);

describe('importServices: catalog', () => {
  it('creates every price-list service with its fields, variants, aftercare template and priceFrom normalization', () => {
    const { db, opts } = setup();
    const templates = db.select().from(aftercareTemplates).orderBy(asc(aftercareTemplates.id)).all();
    const templateId = (category: string) => templates.find((t) => t.category === category)!.id;

    const summary = importServices(db, opts, NOW);

    expect(summary.mode).toBe('apply');
    expect(summary.services.created).toEqual(PRICE_LIST.map((e) => e.name));
    expect(summary.services.matched).toEqual([]);
    const rows = allServices(db);
    expect(rows).toHaveLength(PRICE_LIST.length);
    PRICE_LIST.forEach((entry, index) => {
      expect(rows[index]).toMatchObject({
        name: entry.name,
        category: entry.category,
        groupName: entry.group,
        price: entry.price,
        priceMax: entry.priceMax ?? null,
        durationMin: entry.durationMin,
        description: entry.description,
        imagePrompt: entry.imageSubject,
        imageUrl: null,
        photosJson: '[]',
        aftercareTemplateId: entry.aftercare ? templateId(entry.aftercare) : null,
        active: true,
        sort: (index + 1) * 10,
        createdAt: NOW,
      });
      expect(parseVariants(rows[index]!.variantsJson)).toEqual(entry.variants ?? []);
      if (entry.priceMax !== undefined) expect(rows[index]!.priceFrom).toBe(true);
    });
    expect(serviceNamed(db, 'Среднее тату до 10 см')).toMatchObject({ price: 0, priceMax: 10000, priceFrom: true });
    expect(serviceNamed(db, 'Мини тату до 5 см')).toMatchObject({ price: 2000, priceMax: 5000, priceFrom: true });
    expect(serviceNamed(db, 'Тату больше 15 см')).toMatchObject({ price: 15000, priceMax: null, priceFrom: true });
    expect(serviceNamed(db, 'Консультация по тату')).toMatchObject({ price: 0, priceFrom: false, aftercareTemplateId: null });
    expect(parseVariants(serviceNamed(db, 'Соски').variantsJson)).toEqual([
      { name: 'Один', price: 2500, durationMin: null },
      { name: 'Два', price: 4000, durationMin: 60 },
    ]);
  });

  it('matches the existing «До 5СМ» and «Мочка» instead of duplicating them and only fills their empty fields', () => {
    const { db, opts } = setup();
    const mini = addService(db, { name: 'До 5СМ', category: 'tattoo', price: 2000, priceFrom: true, durationMin: 75 });
    const lobe = addService(db, { name: 'Мочка', category: 'piercing', price: 1600, durationMin: 30, description: 'Своё описание' });
    const tattooTemplate = db.select().from(aftercareTemplates).where(eq(aftercareTemplates.category, 'tattoo')).get()!;

    const summary = importServices(db, opts, NOW);

    expect(summary.services.matched).toEqual([
      { existing: 'До 5СМ', priceList: 'Мини тату до 5 см' },
      { existing: 'Мочка', priceList: 'Мочка' },
    ]);
    expect(summary.services.created).toHaveLength(PRICE_LIST.length - 2);
    expect(summary.services.updated).toBe(2);
    expect(allServices(db)).toHaveLength(PRICE_LIST.length);
    expect(serviceById(db, mini.id)).toMatchObject({
      name: 'До 5СМ',
      price: 2000,
      priceMax: 5000,
      priceFrom: true,
      durationMin: 75,
      groupName: 'Тату',
      description: entryByKey('tattoo-mini').description,
      imagePrompt: entryByKey('tattoo-mini').imageSubject,
      aftercareTemplateId: tattooTemplate.id,
      sort: 0,
      updatedAt: NOW,
    });
    expect(serviceById(db, lobe.id)).toMatchObject({ name: 'Мочка', description: 'Своё описание', groupName: 'Ухо', sort: 0 });
  });

  it('with --update-existing overwrites the price-list fields but keeps duration, active, photos and the picture', () => {
    const { db, opts } = setup();
    fs.writeFileSync(path.join(opts.imagesDir, 'tattoo-mini.jpg'), JPEG);
    const mini = addService(db, {
      name: 'До 5СМ',
      category: 'tattoo',
      price: 1500,
      durationMin: 75,
      active: false,
      description: 'старое',
      photosJson: '["/uploads/work.jpg"]',
      imageUrl: '/uploads/old.jpg',
      variantsJson: '[{"name":"Своё","price":100,"durationMin":null}]',
    });
    addService(db, { name: 'Мочка', category: 'piercing', price: 1600, durationMin: 30 });

    const summary = importServices(db, { ...opts, updateExisting: true }, NOW);

    expect(summary.services.matched.map((m) => m.existing)).toEqual(['До 5СМ', 'Мочка']);
    expect(summary.services.imagesAttached).toBe(0);
    expect(allServices(db)).toHaveLength(PRICE_LIST.length);
    expect(serviceById(db, mini.id)).toMatchObject({
      name: 'Мини тату до 5 см',
      groupName: 'Тату',
      price: 2000,
      priceMax: 5000,
      priceFrom: true,
      description: entryByKey('tattoo-mini').description,
      variantsJson: '[]',
      sort: 20,
      imagePrompt: entryByKey('tattoo-mini').imageSubject,
      durationMin: 75,
      active: false,
      photosJson: '["/uploads/work.jpg"]',
      imageUrl: '/uploads/old.jpg',
    });
    expect(uploadedFiles(opts.uploadsDir)).toEqual([]);
  });

  it('is idempotent in both modes: a re-run creates and changes nothing', () => {
    const { db, opts } = setup();
    fs.writeFileSync(path.join(opts.imagesDir, 'lobe.jpg'), JPEG);
    addService(db, { name: 'До 5СМ', category: 'tattoo', price: 2000, priceFrom: true, durationMin: 75 });
    addService(db, { name: 'Мочка', category: 'piercing', price: 1600, durationMin: 30 });
    importServices(db, opts, NOW);

    const again = importServices(db, opts, NOW + 1);
    const updating = importServices(db, { ...opts, updateExisting: true }, NOW + 2);
    const updatingAgain = importServices(db, { ...opts, updateExisting: true }, NOW + 3);

    expect(again.services).toMatchObject({ created: [], updated: 0, imagesAttached: 0 });
    expect(again.services.matched).toHaveLength(PRICE_LIST.length);
    expect(updating.services).toMatchObject({ created: [], updated: 2 }); // the two pre-existing services get renamed / re-sorted
    expect(updatingAgain.services).toMatchObject({ created: [], updated: 0, imagesAttached: 0 });
    expect(updatingAgain.services.matched).toHaveLength(PRICE_LIST.length);
    expect(allServices(db)).toHaveLength(PRICE_LIST.length);
    expect(uploadedFiles(opts.uploadsDir)).toHaveLength(1);
  });

  it('copies pictures into uploads (preferring .jpg) and sets imageUrl', () => {
    const { db, opts } = setup();
    fs.writeFileSync(path.join(opts.imagesDir, 'lobe.jpg'), JPEG);
    fs.writeFileSync(path.join(opts.imagesDir, 'lobe.png'), PNG);
    fs.writeFileSync(path.join(opts.imagesDir, 'helix.png'), PNG);

    const summary = importServices(db, opts, NOW);

    expect(summary.services.imagesAttached).toBe(2);
    expect(summary.services.missingImages).toEqual(PRICE_LIST.map((e) => e.key).filter((k) => k !== 'lobe' && k !== 'helix'));
    const lobeUrl = serviceNamed(db, 'Мочка').imageUrl!;
    const helixUrl = serviceNamed(db, 'Хеликс').imageUrl!;
    expect(lobeUrl).toMatch(/^\/uploads\/[0-9a-f-]{36}\.jpg$/);
    expect(helixUrl).toMatch(/^\/uploads\/[0-9a-f-]{36}\.png$/);
    const lobeFile = path.join(opts.uploadsDir, path.basename(lobeUrl));
    expect(fs.readFileSync(lobeFile)).toEqual(JPEG);
    expect(fs.statSync(lobeFile).mode & 0o777).toBe(0o644);
    expect(fs.readFileSync(path.join(opts.uploadsDir, path.basename(helixUrl)))).toEqual(PNG);
    expect(uploadedFiles(opts.uploadsDir)).toHaveLength(2);
  });

  it('dry-run writes nothing and copies no files, but reports what a real run does', () => {
    const { db, opts, clientId } = setup();
    fs.writeFileSync(path.join(opts.imagesDir, 'lobe.jpg'), JPEG);
    addService(db, { name: 'До 5СМ', category: 'tattoo', price: 2000, priceFrom: true, durationMin: 75 });
    const visit = addAppointment(db, clientId, 'LOBE Мочка + ROOK Руук', 4000);

    const dry = importServices(db, { ...opts, apply: false, linkHistory: true }, NOW);

    expect(dry.mode).toBe('dry-run');
    expect(dry.services.created).toHaveLength(PRICE_LIST.length - 1);
    expect(dry.history).toMatchObject({ appointmentsLinked: 1, linesCreated: 2 });
    expect(allServices(db).map((s) => s.name)).toEqual(['До 5СМ']);
    expect(serviceNamed(db, 'До 5СМ').updatedAt).toBe(BEFORE);
    expect(lineCount(db)).toBe(0);
    expect(appointmentById(db, visit.id)).toMatchObject({ title: 'LOBE Мочка + ROOK Руук', serviceId: null, updatedAt: BEFORE });
    expect(uploadedFiles(opts.uploadsDir)).toEqual([]);

    const real = importServices(db, { ...opts, linkHistory: true }, NOW);
    expect(real).toEqual({ ...dry, mode: 'apply' });
  });

  it('removes copied pictures when the transaction fails', () => {
    const { db, sqlite, opts, clientId } = setup();
    fs.writeFileSync(path.join(opts.imagesDir, 'lobe.jpg'), JPEG);
    addAppointment(db, clientId, 'Пупок', 2500);
    sqlite.exec(`CREATE TRIGGER fail_lines BEFORE INSERT ON appointment_services BEGIN SELECT RAISE(ABORT, 'boom'); END`);

    expect(() => importServices(db, { ...opts, linkHistory: true }, NOW)).toThrow('boom');

    expect(uploadedFiles(opts.uploadsDir)).toEqual([]);
    expect(allServices(db)).toHaveLength(0);
  });
});

describe('importServices: history linking', () => {
  it('turns YCLIENTS titles into service lines, splits the price and sets service_id, keeping the title', () => {
    const { db, opts, clientId } = setup();
    const existingLobe = addService(db, { name: 'Мочка', category: 'piercing', price: 1600, durationMin: 30 });
    const single = addAppointment(db, clientId, 'Пупок', 2500);
    const multi = addAppointment(db, clientId, 'LOBE Мочка + ROOK Руук', 4000);
    const compound = addAppointment(db, clientId, 'Замена украшения + чистка прокола', 500);
    const mixed = addAppointment(db, clientId, 'ТАТУ + Хеликс', 7001);
    const cartilage = addAppointment(db, clientId, 'Хеликс/хрящ + Конч', 3600);
    const pistol = addAppointment(db, clientId, 'Прокол мочки (пистолет)', 1600);
    const brows = addAppointment(db, clientId, 'Коррекция бровей', 1000);
    const native = addAppointment(db, clientId, 'Тату на предплечье, эскиз согласован', 8000);
    const noTitle = addAppointment(db, clientId, null, 1500);
    const linked = addAppointment(db, clientId, 'Пупок', 2500);
    db.insert(appointmentServices).values({ appointmentId: linked.id, serviceId: null, name: 'Своя строка', price: 2500, position: 0 }).run();

    const summary = importServices(db, { ...opts, linkHistory: true }, NOW);

    const id = (name: string) => serviceNamed(db, name).id;
    expect(linesOf(db, single.id)).toEqual([{ serviceId: id('Пупок'), name: 'Пупок', price: 2500, durationMin: 30, position: 0 }]);
    expect(appointmentById(db, single.id)).toMatchObject({ serviceId: id('Пупок'), title: 'Пупок', updatedAt: NOW });
    expect(linesOf(db, multi.id)).toEqual([
      { serviceId: existingLobe.id, name: 'Мочка', price: 1777, durationMin: 30, position: 0 },
      { serviceId: id('Рук'), name: 'Рук', price: 2223, durationMin: 30, position: 1 },
    ]);
    expect(appointmentById(db, multi.id)).toMatchObject({ serviceId: existingLobe.id, title: 'LOBE Мочка + ROOK Руук' });
    expect(linesOf(db, compound.id)).toEqual([
      { serviceId: id('Замена украшения с чисткой прокола'), name: 'Замена украшения с чисткой прокола', price: 500, durationMin: 30, position: 0 },
    ]);
    expect(linesOf(db, mixed.id)).toEqual([
      { serviceId: null, name: 'Тату', price: 3501, durationMin: null, position: 0 },
      { serviceId: id('Хеликс'), name: 'Хеликс', price: 3500, durationMin: 30, position: 1 },
    ]);
    expect(appointmentById(db, mixed.id)).toMatchObject({ serviceId: id('Хеликс'), title: 'ТАТУ + Хеликс', price: 7001 });
    expect(linesOf(db, cartilage.id).map((l) => [l.name, l.price])).toEqual([['Хеликс', 1800], ['Конч', 1800]]);
    expect(linesOf(db, pistol.id).map((l) => [l.serviceId, l.name, l.price])).toEqual([[existingLobe.id, 'Мочка', 1600]]);
    for (const skipped of [brows, native, noTitle]) {
      expect(linesOf(db, skipped.id)).toEqual([]);
      expect(appointmentById(db, skipped.id)).toEqual(skipped);
    }
    expect(linesOf(db, linked.id).map((l) => l.name)).toEqual(['Своя строка']);
    expect(appointmentById(db, linked.id)).toEqual(linked);
    expect(summary.history).toEqual({
      appointmentsLinked: 6,
      linesCreated: 9,
      skippedUnmapped: 2,
      mappedByService: { Мочка: 2, Хеликс: 2, 'Замена украшения с чисткой прокола': 1, Конч: 1, Пупок: 1, Рук: 1 },
      unmapped: { 'Коррекция бровей': 1, ТАТУ: 1, 'Тату на предплечье, эскиз согласован': 1 },
      sampleLinked: [
        { title: 'Пупок', lines: ['Пупок'] },
        { title: 'LOBE Мочка + ROOK Руук', lines: ['Мочка', 'Рук'] },
        { title: 'Замена украшения + чистка прокола', lines: ['Замена украшения с чисткой прокола'] },
        { title: 'ТАТУ + Хеликс', lines: ['Тату', 'Хеликс'] },
        { title: 'Хеликс/хрящ + Конч', lines: ['Хеликс', 'Конч'] },
        { title: 'Прокол мочки (пистолет)', lines: ['Мочка'] },
      ],
    });
  });

  it('is idempotent: linked appointments are skipped on a re-run', () => {
    const { db, opts, clientId } = setup();
    addAppointment(db, clientId, 'LOBE Мочка + ROOK Руук', 4000);
    addAppointment(db, clientId, 'Коррекция бровей', 1000);
    importServices(db, { ...opts, linkHistory: true }, NOW);

    const again = importServices(db, { ...opts, linkHistory: true }, NOW + 1);

    expect(again.history).toMatchObject({ appointmentsLinked: 0, linesCreated: 0, skippedUnmapped: 1, mappedByService: {}, sampleLinked: [] });
    expect(lineCount(db)).toBe(2);
  });

  it('keeps re-running the YCLIENTS appointment import safe: a linked visit is still recognized by its title', () => {
    const { db, opts } = setup();
    const visit: VisitImportRecord = {
      masterName: 'Админ',
      clientName: 'Анна',
      clientPhone: null,
      startsAt: '2026-10-10T12:00:00+03:00',
      durationMin: 60,
      status: 'completed',
      title: 'LOBE Мочка + ROOK Руук',
      price: 3600,
      notes: null,
      createdAt: null,
    };
    expect(importAppointments(db, [visit], { apply: true, source: 'yclients' }, NOW)).toMatchObject({ created: 1 });
    importServices(db, { ...opts, linkHistory: true }, NOW);

    const again = importAppointments(db, [visit], { apply: true, source: 'yclients' }, NOW);

    expect(again).toMatchObject({ created: 0, existing: 1 });
    const rows = db.select().from(appointments).all();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ title: 'LOBE Мочка + ROOK Руук', serviceId: serviceNamed(db, 'Мочка').id });
    expect(lineCount(db)).toBe(2);
  });

  it('leaves history alone without --link-history', () => {
    const { db, opts, clientId } = setup();
    const visit = addAppointment(db, clientId, 'Пупок', 2500);

    const summary = importServices(db, opts, NOW);

    expect(summary.history).toBeNull();
    expect(lineCount(db)).toBe(0);
    expect(appointmentById(db, visit.id).title).toBe('Пупок');
  });
});

describe('import-services helpers', () => {
  it('splits a price proportionally and gives the rounding remainder to the heaviest line', () => {
    expect(splitPrice(4000, [1600, 2000])).toEqual([1777, 2223]);
    expect(splitPrice(100, [1, 1, 1])).toEqual([34, 33, 33]);
    expect(splitPrice(0, [1800, 1800])).toEqual([0, 0]);
    expect(splitPrice(2500, [2500])).toEqual([2500]);
  });

  it('prettifies ALL-CAPS names only', () => {
    expect(prettifyName('ТАТУ')).toBe('Тату');
    expect(prettifyName('  LOBE   2 ')).toBe('Lobe 2');
    expect(prettifyName('Коррекция бровей')).toBe('Коррекция бровей');
    expect(prettifyName('Я')).toBe('Я');
  });

  it('parses the command line and rejects unknown arguments', () => {
    expect(parseArgs(['--apply', '--link-history', '--images=pics'], '/srv/data', '/app')).toEqual({
      apply: true,
      updateExisting: false,
      linkHistory: true,
      imagesDir: '/app/pics',
      uploadsDir: '/srv/data/uploads',
    });
    expect(parseArgs([], './data', '/app')).toMatchObject({
      apply: false,
      imagesDir: '/app/assets/service-images',
      uploadsDir: '/app/data/uploads',
    });
    expect(parseArgs(['--aply'], './data', '/app')).toBeNull();
    expect(parseArgs(['--images='], './data', '/app')).toBeNull();
  });
});
